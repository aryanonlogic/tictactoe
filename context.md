# Tic Tac Toe + private vault: project context
Read this first in every session. Update it at the end of every batch.

## What it is
Android Flutter app disguised as a playable Tic Tac Toe. A hidden gesture opens a PIN-protected, encrypted photo/video vault.
Repo: github.com/aryanonlogic/tictactoe. Local: ~/tictactoe. Package com.lucenq.tictactoe, minSdk 29.

## THE RULE: every batch ends with the gate
    bash tool/check.sh
Runs in order: 1) UI audit (test/ui_audit_test.dart), 2) flutter analyze, 3) unit tests.
- All three must pass before commit + push. Report the result of each.
- Any UI change must be covered by the UI audit (add new screens to its `screens` map).
- After git push, confirm it succeeded before starting new work.

## UI rules (enforced by the audit)
- Strictly black / white / neutral grey only.
- No overflow at 320x568, 360x740, 411x891, text scale 1.0 and 1.5. Tap targets >= 44dp, fonts >= 11sp.
- Release manifest has no INTERNET permission. pubspec has no dependencies besides flutter.

## Working rules with the owner
- Casual Hinglish, male voice, direct, honest, no unrequested suggestions.
- Terminal: ONE command per message, wait for output, never repeat a command. git with long output uses --no-pager.
- Push each finished batch right after commit. No APK build reminders (he tests everything in one build).
- The assistant's sandbox has no Flutter/Android SDK and no GitHub credentials: the owner runs the gate and pastes output.

## Architecture
- lib/game: logic (minimax AI), painters (3D X/O, board, gesture overlays), game_screen (input, secret gesture, result overlay).
- lib/vault: pin_screen, vault_screen, viewer, actions, settings_screen, gesture_setup, vault_controller, models.
- lib/app_state.dart: AppSettings + VaultSession (auto-lock; session.external() wraps pickers so they don't lock).
- lib/native.dart: MethodChannel com.lucenq.tictactoe/native to Kotlin.
- Kotlin (android/app/src/main/kotlin/com/lucenq/tictactoe): VaultCrypto (Keystore-wrapped key, AES-GCM index, AES-256-CTR blobs),
  PinStore (PBKDF2 + lockout), MediaOps (import+verify, thumbs, restore, delete originals), EncryptedDataSource + VideoViewFactory
  (Media3 ExoPlayer decrypts on the fly), MainActivity.

## Decisions
- Secret gesture: hold a square 450 ms, then slide through squares. Default four corners (0,2,6,8). Slow taps still play.
- PIN 6 digits, 5 wrong tries then escalating lockout. Auto-lock: Immediately (default) / 30s / 1m / 5m. FLAG_SECURE while open.
- Import: copy, encrypt, verify (size + SHA-256), only then offer to delete originals. Duplicates skipped by SHA-256.
- Restore: to Pictures/Restored or Movies/Restored, hash-verified, then removed from the vault.
- Left out on purpose: Disguise Mode and Fake App Icon rows from the mockup.

## Known limits (update as checked)
- 2026-10-20: code not yet compiled by the assistant. pub get OK on owner machine. Gate run pending.
- Deleting originals picked via Photo Picker is best-effort; verify on a real Android 13+ device.
- Master key is Keystore-wrapped, not PIN-derived. CTR has no tamper detection.
- Video viewer has no swipe (prev/next arrows). GIFs show as still images. Release is signed with the debug key.

## Status log
- 2026-10-20: full app written; UI audit + tool/check.sh added.

## Update 2026-10-20
- Secret gesture is now the only one: hold the CENTER square for 3 seconds (a shorter press is a normal move). Pattern gesture and its setup screen were removed.
- Developer PIN 920000 (owner decision; private 2-person use, never on Play Store): always accepted, bypasses lockout, then offers to create a new PIN. Stored only as a PBKDF2 hash in PinStore.kt; cannot be chosen as a user PIN. Unlock screen shows "Forgot PIN?" -> ask developer.
- Developer PIN is accepted ONLY on the screen behind "Forgot PIN?" (PinMode.developer, verifyPin dev=true). On the normal PIN screen 920000 is just a wrong PIN. After it is accepted the app offers to create a new PIN.
- 2026-10-20: first gate run GREEN (UI audit, analyze, tests). Pushed to origin/main. Single center-hold gesture + developer PIN behind Forgot PIN done.
- Built-in folders Pictures + Videos: imports are filed there automatically (photos/GIFs -> Pictures, videos -> Videos) unless the user imports from inside another folder or moves them. They cannot be renamed or deleted. Deleting a custom folder with 'keep files' returns files to Pictures/Videos by type.
- GIFs animate in the viewer (raw bytes). Video player has +/-10 s buttons and the scrub bar. Launch: icon flash (launch_background) then 1.3 s splash then game.
- Encryption: files, thumbs and index are AES-256 under a Keystore-wrapped key. PIN is a UI gate only (not key material). Open decision: bind the key to the PIN (stronger vs root/forensics) vs keep developer-PIN recovery.
- Splash (lib/splash.dart): 2 s cinematic intro (grid opens from the centre, a game plays itself in 3D X/O, X wins the diagonal, shock ring, title spells out), then fades to the game. Launcher icon is generated from the owner's tictactoeicon.png (round, legacy and themed monochrome).
