# Releasing a new version of the phone app

The app is never sent to anyone by hand. You build it once, upload it on the website, press Publish, and every phone installs it from inside the app.

## Every release (about 10 minutes)
1. **Raise the build number** in `flutter_app/pubspec.yaml`: `version: 1.5.0+5` -> `1.5.1+8`. The number after `+` MUST go up every time (phones compare only that number). The upload is refused if it is not higher than what phones already have.
2. **Build it signed with the shop's key** (the file `android/key.properties` + the `.jks` next to it; keep both safe and backed up: an update signed with another key cannot be installed over the old app, people would have to uninstall first and lose their login):
   ```
   cd flutter_app
   flutter build apk --release
   ```
   (no `--dart-define`: that makes the production app; `API_ENV=local` builds are for testing only). The file is `build/app/outputs/flutter-apk/app-release.apk`.
3. **Website > Admin Control > App updates > 1. Upload the new app.** Choose the file. The server opens it, reads the package, version and build number from inside it, refuses a wrong app or a build number that is not higher, and keeps it as "staged". Nothing reaches the phones yet.
4. **2. Review and publish.** Check the version and size, write one line of what is new (optional), tick "Everyone must update" only for something important, press **Publish**.
5. What happens next, by itself: every phone that is open gets the update pop-up at once (live message); the others get a push notification; everyone gets a line in the bell; the update screen shows a progress bar, downloads the file from the server, checks it against its fingerprint (SHA-256) and hands it to Android, which asks "Install?" once.

## Good to know
- **Where the file lives**: on the API server, in `backend/storage/apk/` (never in git). It is served at `GET /api/app-version/download` (public, resumable). The last three published files are kept (for a rollback); older ones are deleted. Do not clear this folder when redeploying the backend.
- **A phone that is far behind** still updates in one step (the newest file is the whole app).
- **A required update** (`forceUpdate`) cannot be closed; it stays until the app is updated.
- **Phones need Android 6.0 or newer** (the in-app installer needs it). The first time, Android may ask to "allow installing apps from this app": the pop-up says so if it is refused.
- **Upload limits**: the website's PHP must accept a file of the APK's size (about 45 MB, set 150 MB to be safe): `upload_max_filesize` and `post_max_size` (see `portal/DEPLOY.md`). `dev-portal.ps1` already raises them for local testing.
- **A mistake** (wrong file published): upload the fixed build with a higher number and publish again. There is no "unpublish": phones that already installed it get the newer one.
- **The first update to this system**: phones that have a version older than the in-app updater (before 1.5.0) still need ONE manual install of 1.5.0 (from the old download page); after that, every update comes from inside the app.

## What staff see on their phone (tested on a real phone, 4 Oct 2026)
1. The update pop-up appears by itself within seconds of Publish (or at the next app start, or from the bell). Tap **Update**: a progress bar, then Android's own screens.
2. **First time only, per phone**: "your phone is not allowed to install unknown apps from this source" -> **Settings** -> switch **Allow from this source** on -> Back. It is asked once; later updates skip it.
3. **Google Play Protect** may show "App scan recommended" -> **Scan app** (about a minute) -> "This app looks safe" -> **Install**. Tell staff to wait for it and not to press "Don't install". Do NOT cancel in the middle: Android then reports "App not installed".
4. "Do you want to install an update to this existing application? Your existing data will not be lost." -> **Install**. The app restarts on the new version; they stay signed in.

## If an update ever fails
- "App not installed": almost always Play Protect was cancelled / dismissed, or the phone has a copy signed with a different key (installed from somewhere else). Try again and let the scan finish; if it is a different key, the old app must be uninstalled once (the person signs in again).
- A copy built with `API_ENV=local` or a debug build can never be updated from the website (different signature or address): only the signed production build is for the shop's phones.
- The same file installs fine with `adb install` (which skips Play Protect): so if adb works but the phone does not, it is Play Protect / the install permission, not the file.

## Checks the server does for you
Not an APK / damaged zip, wrong package name, build number not above what is live, file too large (300 MB), and the fingerprint (SHA-256) the phone verifies after the download.
