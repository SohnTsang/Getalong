# Asset catalog

Image sets in this catalog are referenced from Swift via `Image("Name")`.

## Brand marks (Google / X)

These are intentionally empty placeholders. The official brand kits must
be downloaded by hand and dropped into the matching `.imageset` folder
because both Google and X gate their brand assets on accepting their
brand guidelines.

### `BrandGoogleG.imageset`
- Source: <https://developers.google.com/identity/branding-guidelines>
- Drop in: `google-g.png`, `google-g@2x.png`, `google-g@3x.png`
- Use the unmodified colour "G" mark — do not recolour or recreate.

### `BrandX.imageset`
- Source: <https://about.x.com/en/who-we-are/brand-toolkit>
- Drop in (light appearance, X mark suitable for light backgrounds):
  `x-light.png`, `x-light@2x.png`, `x-light@3x.png`
- Drop in (dark appearance, X mark suitable for dark backgrounds):
  `x-dark.png`, `x-dark@2x.png`, `x-dark@3x.png`
- Use the unmodified mark — monochrome only, do not tint, tilt, or animate.

The Swift code already references `BrandGoogleG` and `BrandX`. Once the
PNGs are dropped in place, no code changes are needed — just rebuild.
