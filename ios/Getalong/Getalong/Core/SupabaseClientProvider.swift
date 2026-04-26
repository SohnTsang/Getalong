import Foundation
import Supabase

/// Centralised configuration for the Supabase client.
///
/// Real values are read from `Secrets.plist` at runtime. The plist is
/// gitignored. See `ios/README.md` for setup.
///
/// IMPORTANT: only the **anon** key may live in the app. The service role
/// key must never ship in any client.
enum SupabaseConfig {
    static let url: URL = {
        guard let raw = Self.value(for: "SUPABASE_URL"),
              let url = URL(string: raw) else {
            preconditionFailure("Missing SUPABASE_URL in Secrets.plist")
        }
        return url
    }()

    static let anonKey: String = {
        guard let key = Self.value(for: "SUPABASE_ANON_KEY"), !key.isEmpty else {
            preconditionFailure("Missing SUPABASE_ANON_KEY in Secrets.plist")
        }
        return key
    }()

    private static func value(for key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, format: nil
              ) as? [String: Any]
        else { return nil }
        return plist[key] as? String
    }
}

/// Calls an Edge Function and returns the raw response bytes.
///
/// Why this exists: supabase-swift's `invoke<T: Decodable>` overload is
/// picked when callers write `let raw: Data = ...invoke(...)`. That
/// overload runs `JSONDecoder().decode(Data.self, from: response)` —
/// which expects a base64 *string*, not a JSON object body, and fails
/// every time with `NSCocoaErrorDomain 3840` ("data couldn't be read").
/// Forcing the closure variant returns the raw bytes verbatim and lets
/// each service decode our envelope shape on its own terms.
extension Supa {
    static func invokeRaw(
        _ functionName: String,
        body: some Encodable
    ) async throws -> Data {
        try await client.functions.invoke(
            functionName,
            options: .init(body: body)
        ) { data, _ in data }
    }

    static func invokeRaw(_ functionName: String) async throws -> Data {
        try await client.functions.invoke(functionName) { data, _ in data }
    }

    /// Walks a thrown error's reflection graph and returns the first
    /// `Data` field it finds. supabase-swift surfaces non-2xx Edge
    /// Function responses as `FunctionsError.httpError(code:Int, data:Data)`
    /// — the `data` payload contains our own error envelope, but it's
    /// nested two levels deep (enum case → associated tuple → labeled
    /// fields), which a one-level Mirror walk misses.
    static func errorBody(from error: Error) -> Data? {
        var queue: [Any] = [error]
        while let current = queue.popLast() {
            if let data = current as? Data { return data }
            let mirror = Mirror(reflecting: current)
            for child in mirror.children {
                queue.append(child.value)
            }
        }
        return nil
    }
}

/// Single shared `SupabaseClient`. Services and `SessionManager` go
/// through this. Built on first access.
enum Supa {
    static let client: SupabaseClient = {
        SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    // Opt in to the upcoming default: emit the locally
                    // cached session immediately on launch so we don't
                    // briefly flash the SignInView while the SDK refreshes.
                    // The SessionManager listener already filters by event
                    // type, and we re-resolve on `tokenRefreshed`.
                    // See https://github.com/supabase/supabase-swift/pull/822
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }()

    /// JSON decoder used wherever we hand-decode bytes (e.g. Edge Function
    /// envelopes). Tolerant to ISO-8601 with or without fractional seconds.
    static let jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: s) { return d }
            f.formatOptions = [.withInternetDateTime]
            if let d = f.date(from: s) { return d }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Invalid ISO-8601 date: \(s)"
            ))
        }
        return d
    }()
}
