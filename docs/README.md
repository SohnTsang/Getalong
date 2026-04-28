# Getalong website

Static HTML/CSS only. No build step. No JS frameworks.

## Layout

```
web/
  index.html             landing
  privacy/
    index.html           English
    ja/index.html        日本語
    zh-Hant/index.html   繁體中文
  terms/
    index.html
    ja/index.html
    zh-Hant/index.html
  support/index.html
  assets/styles.css
```

## Local preview

```bash
python3 -m http.server 8080 --directory web
```

Open: <http://localhost:8080/>

Visit:

- `/` — landing
- `/privacy/`, `/privacy/ja/`, `/privacy/zh-Hant/`
- `/terms/`, `/terms/ja/`, `/terms/zh-Hant/`
- `/support/`

## Deployment

Pushes to `main` that touch `web/**` trigger
[`.github/workflows/pages.yml`](../.github/workflows/pages.yml) which
publishes the `web/` folder to GitHub Pages via the official
`actions/configure-pages` + `actions/upload-pages-artifact` +
`actions/deploy-pages` chain.

To enable GitHub Pages for this repo:

1. GitHub → Settings → Pages → "Build and deployment" source = **GitHub Actions**.
2. Push to `main`. The workflow runs and the URL appears under the `github-pages` environment.

## Custom domain

When `getalong.app` is connected:

- Add a `CNAME` file at `web/CNAME` containing `getalong.app`.
- Configure the DNS:
  - apex `A` records to GitHub Pages IPs, or
  - subdomain `CNAME` to `<owner>.github.io`.
- In Settings → Pages, set the custom domain and tick **Enforce HTTPS**.

The App Store metadata privacy URL should point at <https://getalong.app/privacy/>.

## Legal pages — important

The privacy and terms pages are **working drafts** based on
`marketing/legal/PRIVACY_POLICY.*.md`. Have a privacy/terms lawyer for
the launch markets (US / JP / HK / TW / EU) review them before
publishing publicly. Until then, the pages are deployable but not legal
advice.

## Style direction

- "Quiet Signal" palette: warm off-white in light, deep ink in dark.
- Editorial serif headlines, system sans body.
- Coral ember accent used only on the title accent line and the moment-card pill.
- No template-y feature grids, no fake metrics, no fake testimonials,
  no AI-startup gradients.
- Mobile-first. Page max-width 1040px; legal pages 760px.
