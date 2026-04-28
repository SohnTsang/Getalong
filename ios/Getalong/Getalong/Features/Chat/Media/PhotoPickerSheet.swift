import SwiftUI
import Photos
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// In-app photo picker shown as a half-sheet (drag up to expand).
///
/// Layout
///   * Fixed 4-column grid → every tile is exactly the same square size.
///   * Top-left tile is a live "Take Photo" button when the device has
///     a camera, so the user doesn't have to bounce out of the chat.
///   * Title bar shows the current album name with a chevron — tapping
///     pushes a separate "Albums" screen (iOS Photos-app pattern)
///     instead of cramming the whole album list into a Menu dropdown.
///
/// Performance
///   * One shared `PHCachingImageManager` per session — cheaper than
///     `PHImageManager.default()` for grid scrolling because it warms
///     a thumbnail cache.
///   * `.highQualityFormat` delivery so callbacks fire once per asset.
///   * `ResumedFlag` guards the continuation against the system
///     occasionally sending a degraded preview before the final image,
///     which would otherwise trap on second resume.
struct PhotoPickerSheet: View {
    let onPicked: (MediaUploadController.PickerSource) -> Void
    let onClose: () -> Void

    @State private var assets: [PHAsset] = []
    @State private var libraryStatus: PHAuthorizationStatus = .notDetermined
    @State private var isCameraPresented = false
    @State private var isResolvingAsset = false
    @State private var resolveError: String?

    @State private var albums: [AlbumChoice] = []
    @State private var selectedAlbum: AlbumChoice = .recents
    /// `NavigationStack` path. Push `albumPickerRoute` to open the
    /// dedicated Albums screen.
    @State private var path: [Route] = []

    enum Route: Hashable { case albumPicker }

    /// Shared caching manager — reused across this sheet's lifetime so
    /// successive scrolls hit the cache rather than re-decoding raw
    /// asset bytes from disk.
    private let imageManager = PHCachingImageManager()

    /// User-album switcher entries. `recents` is a synthetic "all
    /// images" choice so users always have a fallback.
    struct AlbumChoice: Identifiable, Hashable {
        let id: String
        let title: String
        let collection: PHAssetCollection?
        /// Cached count, optional — only filled in for real albums
        /// during the loadAlbums() pass; the synthetic "Recents"
        /// stays `nil` to skip the count badge.
        var count: Int?

        static let recents = AlbumChoice(
            id: "ga.recents",
            title: "Recents",
            collection: nil,
            count: nil
        )
    }

    /// 3-column square grid. Tile size is computed from the actual
    /// container width so every cell is byte-identical — no flexible
    /// or adaptive sizing, no .aspectRatio rounding, no edge padding
    /// on the grid itself. The horizontal and vertical gaps are the
    /// same value so rows and columns visually breathe equally.
    private let gridSpacing: CGFloat = 2
    private let gridColumnCount: Int = 3
    private let assetFetchLimit = 240

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                GAColors.background.ignoresSafeArea()

                Group {
                    switch libraryStatus {
                    case .authorized, .limited:
                        grid
                    case .denied, .restricted:
                        deniedState
                    case .notDetermined:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    @unknown default:
                        deniedState
                    }
                }
                .overlay(alignment: .bottom) {
                    if let err = resolveError {
                        GAErrorBanner(message: err,
                                      onDismiss: { resolveError = nil })
                            .padding(GASpacing.lg)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { titleButton }
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel"), action: onClose)
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .albumPicker:
                    AlbumListView(
                        albums: albums,
                        imageManager: imageManager,
                        selected: selectedAlbum,
                        onPick: { choice in
                            selectedAlbum = choice
                            path.removeAll()
                        }
                    )
                }
            }
            .task { await ensureLibraryAccess() }
            // Reload whenever the user switches album. Using `.task(id:)`
            // (keyed on the album id) guarantees the previous load is
            // cancelled before the next one starts — `.onChange + Task`
            // could otherwise race and stamp the older results last.
            .task(id: selectedAlbum.id) {
                guard libraryStatus == .authorized || libraryStatus == .limited else { return }
                await loadAssets(in: selectedAlbum.collection)
            }
            .sheet(isPresented: $isCameraPresented) {
                CameraCaptureSheet { data in
                    isCameraPresented = false
                    if let data {
                        onPicked(.imageData(data, sourceMime: "image/jpeg"))
                    }
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Title button (push to albums)

    private var titleButton: some View {
        Button {
            path.append(.albumPicker)
        } label: {
            HStack(spacing: 4) {
                Text(selectedAlbum.title)
                    .font(GATypography.bodyEmphasized)
                    .foregroundStyle(GAColors.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(GAColors.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("media.picker.album.choose"))
    }

    // MARK: - Grid

    private var grid: some View {
        GeometryReader { proxy in
            // tile = (width − spacing × (n−1)) / n. No outer padding —
            // the grid runs edge-to-edge so the gap between tiles is
            // the only visual breathing room. Floor to an integer to
            // avoid sub-pixel rounding that would otherwise produce
            // hairline width differences between columns.
            let cols = CGFloat(gridColumnCount)
            let totalSpacing = gridSpacing * (cols - 1)
            let usable = max(0, proxy.size.width - totalSpacing)
            let tile = floor(usable / cols)
            let columns = Array(
                repeating: GridItem(.fixed(tile), spacing: gridSpacing),
                count: gridColumnCount
            )

            ScrollView {
                LazyVGrid(columns: columns, spacing: gridSpacing) {
                    if cameraAvailable {
                        cameraTile(size: tile)
                    }
                    ForEach(assets, id: \.localIdentifier) { asset in
                        AssetThumbnail(asset: asset, imageManager: imageManager) {
                            Task { await pick(asset) }
                        }
                        .frame(width: tile, height: tile)
                    }
                }
            }
            .overlay {
                if isResolvingAsset {
                    ProgressView()
                        .padding(GASpacing.lg)
                        .background(.ultraThinMaterial,
                                    in: RoundedRectangle(cornerRadius: GACornerRadius.medium))
                }
            }
        }
    }

    private func cameraTile(size: CGFloat) -> some View {
        Button {
            isCameraPresented = true
        } label: {
            ZStack {
                Rectangle().fill(GAColors.surfaceRaised)
                VStack(spacing: 6) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(GAColors.textPrimary)
                    Text("media.picker.takePhoto")
                        .font(GATypography.caption.weight(.semibold))
                        .foregroundStyle(GAColors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "media.picker.takePhoto"))
    }

    // MARK: - Permission denied

    private var deniedState: some View {
        GAEmptyState(
            title: String(localized: "media.picker.denied.title"),
            message: String(localized: "media.picker.denied.subtitle"),
            systemImage: "photo.on.rectangle",
            actionTitle: String(localized: "common.openSettings")
        ) {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
        .padding(GASpacing.xl)
    }

    // MARK: - Library auth + fetch

    private func ensureLibraryAccess() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .notDetermined:
            let granted = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            libraryStatus = granted
            if granted == .authorized || granted == .limited {
                await loadAlbums()
                // .task(id: selectedAlbum.id) handles the initial load.
            }
        case .authorized, .limited:
            libraryStatus = status
            await loadAlbums()
        default:
            libraryStatus = status
        }
    }

    /// User albums + smart albums + the synthetic Recents entry.
    /// Counts are cached on each AlbumChoice so the album list view
    /// doesn't have to re-query.
    private func loadAlbums() async {
        let recents = AlbumChoice(
            id: AlbumChoice.recents.id,
            title: String(localized: "media.picker.album.recents"),
            collection: nil,
            count: nil
        )
        let collected = await Task.detached(priority: .userInitiated) {
            () -> [AlbumChoice] in
            var out: [AlbumChoice] = [recents]

            // Smart albums (Favourites, Selfies, Screenshots, etc.)
            let smarts = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum, subtype: .any, options: nil
            )
            smarts.enumerateObjects { col, _, _ in
                if col.assetCollectionSubtype == .smartAlbumAllHidden { return }
                if col.assetCollectionSubtype.rawValue == 1000000201  { return } // Recently Deleted
                let count = PHAsset.fetchAssets(in: col, options: nil).count
                guard count > 0, let title = col.localizedTitle else { return }
                out.append(AlbumChoice(
                    id: col.localIdentifier, title: title,
                    collection: col, count: count
                ))
            }

            // User-created albums
            let userAlbums = PHAssetCollection.fetchAssetCollections(
                with: .album, subtype: .any, options: nil
            )
            userAlbums.enumerateObjects { col, _, _ in
                let count = PHAsset.fetchAssets(in: col, options: nil).count
                guard count > 0, let title = col.localizedTitle else { return }
                out.append(AlbumChoice(
                    id: col.localIdentifier, title: title,
                    collection: col, count: count
                ))
            }
            return out
        }.value

        await MainActor.run {
            self.albums = collected
            // Make sure the default selection picks up the localized
            // "Recents" title (the @State initializer ran before the
            // string catalog was consulted).
            if self.selectedAlbum.id == AlbumChoice.recents.id {
                self.selectedAlbum = recents
            }
        }
    }

    /// Loads images either platform-wide (collection nil = "Recents")
    /// or within a specific PHAssetCollection.
    private func loadAssets(in collection: PHAssetCollection?) async {
        // Clear and stop caching for the previous album immediately so
        // we don't briefly show the wrong album's thumbnails while the
        // new fetch runs.
        imageManager.stopCachingImagesForAllAssets()
        await MainActor.run { self.assets = [] }

        let limit = assetFetchLimit
        let result: [PHAsset] = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let opts = PHFetchOptions()
                opts.sortDescriptors = [
                    NSSortDescriptor(key: "creationDate", ascending: false)
                ]
                opts.fetchLimit = limit
                // Predicate is only safe on the platform-wide fetch —
                // some smart albums (e.g. Favorites) fail to combine
                // their internal selection with a mediaType predicate
                // and return empty. When fetching from a specific
                // collection we filter images out in-process instead.
                if collection == nil {
                    opts.predicate = NSPredicate(
                        format: "mediaType == %d",
                        PHAssetMediaType.image.rawValue
                    )
                }
                let fetch: PHFetchResult<PHAsset> = collection.map {
                    PHAsset.fetchAssets(in: $0, options: opts)
                } ?? PHAsset.fetchAssets(with: opts)
                var collected: [PHAsset] = []
                collected.reserveCapacity(fetch.count)
                fetch.enumerateObjects { asset, _, _ in
                    if asset.mediaType == .image { collected.append(asset) }
                }
                cont.resume(returning: collected)
            }
        }
        // .task(id:) auto-cancels mid-flight; bail out if so.
        if Task.isCancelled { return }
        await MainActor.run {
            self.assets = result
            // Warm the caching manager for the about-to-be-shown
            // tiles. Cheap; reduces first-scroll jank.
            let target = CGSize(width: 240, height: 240)
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .highQualityFormat
            opts.resizeMode = .fast
            imageManager.startCachingImages(
                for: result, targetSize: target,
                contentMode: .aspectFill, options: opts
            )
        }
    }

    // MARK: - Pick

    private func pick(_ asset: PHAsset) async {
        guard !isResolvingAsset else { return }
        isResolvingAsset = true
        resolveError = nil
        defer { isResolvingAsset = false }
        let opts = PHImageRequestOptions()
        opts.isSynchronous = false
        opts.deliveryMode = .highQualityFormat
        opts.isNetworkAccessAllowed = true
        opts.version = .current
        // Get the original UTI alongside the bytes so HEIC / PNG / GIF
        // pass through with their real type instead of being mislabeled
        // as JPEG. ImageCompressor still re-encodes to JPEG for HEIC,
        // preserves PNG-with-alpha and animated GIFs.
        let result: (Data, String?)? = await withCheckedContinuation { cont in
            let resumed = ResumedFlag()
            imageManager.requestImageDataAndOrientation(
                for: asset, options: opts
            ) { data, uti, _, _ in
                guard resumed.tryMark() else { return }
                let mime = uti.flatMap { Self.mimeFor(uti: $0) }
                cont.resume(returning: data.map { ($0, mime) })
            }
        }
        guard let (data, mime) = result else {
            resolveError = String(localized: "media.picker.error.load")
            return
        }
        onPicked(.imageData(data, sourceMime: mime ?? "image/jpeg"))
    }

    /// UTI → MIME mapping for the formats Photos delivers in practice.
    /// Falls back to nil so the caller can default to image/jpeg.
    private static func mimeFor(uti: String) -> String? {
        if let t = UTType(uti)?.preferredMIMEType { return t }
        switch uti {
        case "public.heic":  return "image/heic"
        case "public.jpeg":  return "image/jpeg"
        case "public.png":   return "image/png"
        case "com.compuserve.gif": return "image/gif"
        default: return nil
        }
    }
}

// MARK: - Asset thumbnail

private struct AssetThumbnail: View {
    let asset: PHAsset
    let imageManager: PHCachingImageManager
    let onTap: () -> Void

    @State private var thumbnail: UIImage?

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Rectangle().fill(GAColors.surfaceRaised)
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            // Container clips the scaledToFill thumbnail to the square
            // bounds without imposing a corner radius. The outer
            // .frame in the grid sets the size; we only need the clip.
            .clipped()
        }
        .buttonStyle(.plain)
        .task(id: asset.localIdentifier) { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        let opts = PHImageRequestOptions()
        opts.isSynchronous = false
        opts.deliveryMode = .highQualityFormat
        opts.resizeMode = .fast
        opts.isNetworkAccessAllowed = true
        let target = CGSize(width: 240, height: 240)
        let img: UIImage? = await withCheckedContinuation { cont in
            let resumed = ResumedFlag()
            imageManager.requestImage(
                for: asset, targetSize: target,
                contentMode: .aspectFill, options: opts
            ) { img, _ in
                guard resumed.tryMark() else { return }
                cont.resume(returning: img)
            }
        }
        thumbnail = img
    }
}

// MARK: - Album list (push destination)

private struct AlbumListView: View {
    let albums: [PhotoPickerSheet.AlbumChoice]
    let imageManager: PHCachingImageManager
    let selected: PhotoPickerSheet.AlbumChoice
    let onPick: (PhotoPickerSheet.AlbumChoice) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(albums) { album in
                    Button {
                        onPick(album)
                    } label: {
                        row(album)
                    }
                    .buttonStyle(.plain)
                    Rectangle()
                        .fill(GAColors.border)
                        .frame(height: 0.5)
                        .padding(.leading, 76) // line up under thumb + text
                }
            }
        }
        .background(GAColors.background.ignoresSafeArea())
        .navigationTitle(String(localized: "media.picker.album.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func row(_ album: PhotoPickerSheet.AlbumChoice) -> some View {
        HStack(spacing: GASpacing.md) {
            AlbumThumbnail(album: album, imageManager: imageManager)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(GAColors.border, lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(GATypography.body)
                    .foregroundStyle(GAColors.textPrimary)
                if let count = album.count {
                    Text("\(count)")
                        .font(GATypography.caption)
                        .foregroundStyle(GAColors.textTertiary)
                        .monospacedDigit()
                }
            }

            Spacer()

            if album.id == selected.id {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GAColors.accent)
            }
        }
        .padding(.horizontal, GASpacing.lg)
        .padding(.vertical, GASpacing.sm)
        .contentShape(Rectangle())
    }
}

private struct AlbumThumbnail: View {
    let album: PhotoPickerSheet.AlbumChoice
    let imageManager: PHCachingImageManager

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(GAColors.surfaceRaised)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo.stack")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(GAColors.textTertiary)
            }
        }
        .task(id: album.id) { await load() }
    }

    private func load() async {
        // Recents: use the most-recent image platform-wide.
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opts.fetchLimit = 1
        opts.predicate = NSPredicate(
            format: "mediaType == %d",
            PHAssetMediaType.image.rawValue
        )
        let fetch: PHFetchResult<PHAsset> = album.collection.map {
            PHAsset.fetchAssets(in: $0, options: opts)
        } ?? PHAsset.fetchAssets(with: opts)
        guard let asset = fetch.firstObject else { return }

        let reqOpts = PHImageRequestOptions()
        reqOpts.deliveryMode = .highQualityFormat
        reqOpts.resizeMode = .fast
        reqOpts.isNetworkAccessAllowed = true
        let target = CGSize(width: 168, height: 168)
        let img: UIImage? = await withCheckedContinuation { cont in
            let resumed = ResumedFlag()
            imageManager.requestImage(
                for: asset, targetSize: target,
                contentMode: .aspectFill, options: reqOpts
            ) { img, _ in
                guard resumed.tryMark() else { return }
                cont.resume(returning: img)
            }
        }
        image = img
    }
}

// MARK: - One-shot resume guard

private final class ResumedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func tryMark() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

// MARK: - UIImagePickerController bridge for camera

private struct CameraCaptureSheet: UIViewControllerRepresentable {
    let onCapture: (Data?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            p.sourceType = .camera
            p.cameraCaptureMode = .photo
        } else {
            p.sourceType = .photoLibrary
        }
        p.allowsEditing = false
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (Data?) -> Void
        init(onCapture: @escaping (Data?) -> Void) { self.onCapture = onCapture }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let img = info[.originalImage] as? UIImage
            let data = img?.jpegData(compressionQuality: 0.85)
            onCapture(data)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture(nil)
        }
    }
}
