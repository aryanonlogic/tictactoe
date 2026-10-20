# Tic Tac Toe (with a private vault)

A playable, minimal black-and-white Tic Tac Toe for Android. Hidden inside: a PIN-protected, encrypted photo/video vault.

## Opening the vault
Press and hold any square of the board, then slide through the squares of your gesture (default: the four corners
`top-left → top-right → bottom-left → bottom-right`). Normal taps are never affected. The first time, you create a 6-digit PIN.
Change the gesture, PIN and auto-lock in the vault's Settings. You can also share photos/videos from any gallery app to
"Tic Tac Toe" to import them.

## Build
```
flutter pub get
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```
Needs JDK 17. Android 10+ (minSdk 29).

## Architecture
- `lib/game/*` – game logic (minimax AI), painters (subtle 3D X/O), board input + secret gesture.
- `lib/vault/*` – PIN, gallery, folders, viewer, settings. State lives in `VaultController`.
- `android/.../VaultCrypto.kt` – Keystore-wrapped master key, AES-256-GCM index, AES-256-CTR media blobs (seekable).
- `android/.../EncryptedDataSource.kt` + `VideoViewFactory.kt` – Media3 ExoPlayer plays encrypted videos by decrypting on the fly.
- `android/.../MediaOps.kt` – import + verification, thumbnails, restore to gallery, delete-original mapping.
- No INTERNET permission in the release build, no analytics, backups disabled.
