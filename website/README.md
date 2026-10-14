# Fenyvo website

Static public landing page for `https://fenyvo.com/`.

Deployment layout:

```text
/var/www/fenyvo/
  index.html
  .well-known/assetlinks.json
  assets/fenyvo-logo.png
  download/Fenyvo-1.8.1-arm64.apk
  download/Fenyvo-1.8.1-arm64.sha256.txt
  download/Fenyvo-1.8.1-windows-x64.zip
  download/Fenyvo-1.8.1-windows-x64.sha256.txt
  releases/appcast.json
```

The APK binary is deployed separately and must not be committed to Git. Update
the displayed version, build, size and SHA-256 together with every public APK.
The `/.well-known/assetlinks.json` response must be public, must not redirect,
and must be served with the `application/json` content type for Android App
Links verification.

The landing page automatically follows the browser/device language for Russian,
Ukrainian and English. Other languages fall back to English so the browser's
built-in page translator can translate the site. Visitors can override the
language from the header; the choice is stored only in local browser storage.
The same preference and selector cover `privacy.html`, `terms.html`,
`acceptable-use.html`, and `support.html`; all four include complete Russian,
Ukrainian, and English versions. Legal names and email addresses are not
localized.
The `Fenyvo` wordmark is marked with `translate="no"`/`notranslate`; this protects
the brand name without disabling external translation for the rest of a page.
The generated `fenyvo-network-landscape-20261010.jpg` asset contains no user
data, text or third-party marks. Motion is implemented in CSS and respects the
browser/OS `prefers-reduced-motion` accessibility setting.

The public landing page displays separate Android, Windows and iPhone download
counters. Android and Windows are counted only after the visitor accepts the
download dialog; iPhone remains at zero and is labelled as in development until
an actual iOS package exists. These figures measure download starts, not
completed installations. A server-side timer aggregates privacy-preserving
events from nginx logs, deduplicating the same IP, browser and platform during
one UTC day. Raw IP addresses are not stored in the counter state.
