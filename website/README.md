# Fenyvo website

Static public landing page for `https://fenyvo.com/`.

Deployment layout:

```text
/var/www/fenyvo/
  index.html
  assets/fenyvo-logo.png
  download/Fenyvo-1.8.0-arm64.apk
  download/Fenyvo-1.8.0-arm64.sha256.txt
```

The APK binary is deployed separately and must not be committed to Git. Update
the displayed version, build, size and SHA-256 together with every public APK.
