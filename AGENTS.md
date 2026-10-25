# Fenyvo repository maintenance

The owner requests that after each successfully verified messenger improvement,
reviewed source changes, README status and CHANGELOG are updated here.
Distinguish automated tests from user-confirmed device tests; record limitations.
An unfinished or untested change is not a release.

Never publish runtime user data, personal avatars, message databases, FCM tokens,
API keys, Firebase Admin secrets, signing keys or encrypted DPAPI files.
Review the exact staged paths and diff before committing; use explicit staging.
Keep distributable APK/Windows bundles out of source commits.

The `main` branch is the current reviewed Fenyvo source line. Never overwrite
newer local or remote work with an older snapshot. Keep updates deliberate;
never copy an entire runtime project folder. Local launchers tied to a running
server, caches, SDKs, old manifests and diagnostic files are excluded. Build
paths and private signing keys must be configured locally. Read README build
notes before building on another machine.

Old clones retain the removed data and history. Never merge or push their old
history back here. Future updates use normal fast-forward pushes.
A further history rewrite needs new explicit authorization.

Do not claim a GitHub update succeeded until the remote branch is verified.
If authentication is unavailable, prepare a checked command for the owner and
clearly mark publication as pending. Do not request secrets in chat.
