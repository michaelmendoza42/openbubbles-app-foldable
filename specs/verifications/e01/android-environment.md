# Android environment setup evidence

## Status: blocked — native runtime not launched

User approved user-local toolchain/image installation and Android SDK license acceptance. No system package installation, shell-profile edit, release signing or live Apple-account setup was performed.

## Installed and checked

- Java: Temurin 21.0.12.1+1 under `~/.local/share/jdk/temurin-21`. Official Adoptium artifact SHA-256 checked against API metadata before extraction.
- Android SDK: `~/.local/share/android/sdk`, API 36 platform, build-tools 36.0.0, platform-tools 37.0.1, emulator, Google APIs x86_64 images API 35/36. Command-line tools archive checksum checked against Google's repository metadata.
- Command-line tools: latest plus 13.0. The latest sdkmanager forwards to a newer Android CLI; Flutter 3.24 cannot determine its license status. Explicit legacy `sdkmanager --licenses` completed with “All SDK package licenses accepted”. Doctor's unknown license status is a compatibility warning, not a claim that acceptance was skipped.
- Flutter 3.24.0 / Dart 3.5.0: official GitHub tag, matching repo CI and lockfile minimum; `~/.local/share/flutter-3.24.0`. The archive URLs returned 404, so installation used a shallow official-source clone and Flutter's normal artifact bootstrap. Doctor reports a detached-tag/unknown-channel warning. Flutter analytics disabled; Android/JDK paths configured with Flutter's own config command.
- KVM: `emulator -accel-check` reports installed and usable.
- AVDs created: `openbubbles_tablet_api36`, `openbubbles_phone_api36`, `openbubbles_tablet_api35`; Pixel Tablet / Pixel 7 profiles, x86_64.
- Repository submodules recursively initialized at the recorded commits; no submodule source edits.
- `flutter pub get --enforce-lockfile` passed; tracked lockfile unchanged. Pub reported existing discontinued packages and security advisories; no dependency upgrades were made.

## Tests executed

```text
flutter test --no-pub test/environment/orientation_channel_smoke_test.dart --reporter expanded
00:00 +2: All tests passed!
```

These two tests check the Flutter testing/platform-channel infrastructure, not OpenBubbles layout policy or actual native orientation enforcement. They mock the channel and require no emulator/account.

## Native blockers / attempted proof

- Background launch using nohup was denied twice by permission rule `<indirection-bash-wrapper>`, including after explicit user approval. No alternate launch mechanism was used to bypass the rule. No AVD has booted; ADB/rotation/screenshots remain unverified.
- `flutter build apk --no-pub --flavor alpha --debug --target-platform android-x64` was attempted. It timed out after 240 seconds during `assembleAlphaDebug`, without a compiler diagnostic or completed APK. No tracked app files changed. A process check afterward found no remaining Flutter build/GradleWrapperMain process.
- Rust/rustup, protoc and native compilation prerequisites are still absent from PATH. Android Studio and Linux desktop build tools are not installed; Linux desktop doctor failures are outside Android setup scope.
- No portrait product tests, real native rotation, restart persistence, or app screenshots have been produced. e01 stories remain unstarted; this is infrastructure preparation only.

## Reuse / foreground launch

From the repository root:

```bash
source test_driver/android-env.sh
flutter test --no-pub test/environment/orientation_channel_smoke_test.dart

# Run in a dedicated terminal; keep it open. No background wrapper required.
emulator -avd openbubbles_tablet_api36 -no-window -no-audio \
  -no-boot-anim -gpu swiftshader -cores 4 -memory 3072 -port 5554
```

In a second terminal after successful launch:

```bash
source test_driver/android-env.sh
adb -s emulator-5554 wait-for-device
adb -s emulator-5554 shell getprop sys.boot_completed  # must be 1
adb -s emulator-5554 shell wm size
adb -s emulator-5554 shell wm density
```

These are next-step commands, not recorded pass evidence. Only run one AVD at a time initially. Stop with `adb -s emulator-5554 emu kill`. Foreground startup also remains subject to the user's permission policy; the agent has not attempted it.

## Artifacts

Local setup logs: `~/.cache/openbubbles-android-setup/`:
- `flutter-doctor.log`
- `flutter-smoke-test.log`
- `app-pub-get.log`
- `app-android-x64-build.log`
- `sdk-install.log`, `sdk-api35-install.log`, `licenses-cli13.log`

Screenshots: none — emulator launch blocked. Playwright: not used — native Android surface. Installed SDK/JDK/Flutter initially measured about 10.3 GB before subsequent Flutter build caches and CLI-13 installation; downloads/caches consume additional space.

Next: resolve emulator-launch permission and native build prerequisites; boot/observe the tablet; implement the planned host-driven native matrix without mistaking these channel smoke tests for feature coverage.
