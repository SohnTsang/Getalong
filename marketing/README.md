# Marketing & legal assets

Localized App Store metadata and legal documents for Getalong. The
folder structure mirrors fastlane's `metadata/` convention so it can be
adopted later without renaming anything.

```
marketing/
  AppStore/
    en-US/        # primary App Store locale
      name.txt
      subtitle.txt
      promotional_text.txt
      keywords.txt
      description.txt
    ja/
    zh-Hant/
  legal/
    PRIVACY_POLICY.en.md
    PRIVACY_POLICY.ja.md
    PRIVACY_POLICY.zh-Hant.md
```

## App Store

* **name.txt** — app name. We keep "Getalong" untranslated everywhere.
* **subtitle.txt** — 30 char hard limit per Apple. Current copy is
  comfortably under.
* **promotional_text.txt** — 170 char hard limit. Updateable without a
  binary release.
* **keywords.txt** — 100 chars total, comma-separated, no spaces.
* **description.txt** — long form, plain text, no HTML.

These map 1:1 to App Store Connect fields. If we adopt fastlane later,
move them to `fastlane/metadata/<locale>/` and the same filenames will
be picked up automatically.

## Privacy policy

The three Markdown files are working drafts. **Do not publish** until a
qualified privacy lawyer for the jurisdictions we ship in (US, JP, HK,
TW, EU) has reviewed them. Hosting plan: serve at
`https://getalong.app/privacy/<locale>` and point the App Store privacy
URL there.
