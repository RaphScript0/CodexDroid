# CodexDroid

Android Flutter client + bridge server to control OpenAI Codex CLI remotely.

## Repo Structure
```
bridge-server/   # Node WebSocket proxy for codex app-server
flutter-app/     # Flutter Android client
```

## Quickstart

### 1) Run Codex app-server (on your Linux box)
```bash
codex app-server --listen ws://127.0.0.1:4500
```

### 2) Start bridge server
```bash
cd bridge-server
npm install
npm start
```
Defaults: `BRIDGE_PORT=4501`, `CODEX_APP_SERVER_URL=ws://127.0.0.1:4500`, `START_APP_SERVER=true`

### 3) Run Android app
```bash
cd flutter-app
flutter pub get
flutter run
```
Open **Settings** → set server IP/port (e.g. `192.168.1.100:4501`) → Save & Reconnect.

## Bridge Server
See `bridge-server/README.md` for full JSON-RPC protocol and config details.

## Flutter App
See `flutter-app/README.md` for UI behavior, tests, and usage.

## Signed APK (GitHub Actions)
Workflow: `.github/workflows/android-release.yml`

**Triggers**:
- Push to `main`
- Manual dispatch (Actions tab)

**Required Secrets** (repo settings → Actions → Secrets):
- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

**Keystore creation**:
```bash
keytool -genkey -v -keystore codexdroid.jks -keyalg RSA -keysize 2048 -validity 10000 -alias codexdroid
base64 -w 0 codexdroid.jks > codexdroid.jks.b64
```
Set `ANDROID_KEYSTORE_BASE64` to the contents of `codexdroid.jks.b64`.

**Artifacts**:
- `app-release.apk` uploaded as `app-release-signed`

## Release
Current tag: `v0.1.0`

## Notes
- UI screenshots/visual validation were skipped previously per approval.
