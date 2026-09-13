# e01 native verification contract (planned implementation)

These runner/test files do not exist yet. e01s01 task 0 creates them and declares the SDK `integration_test` dev dependency in pubspec.yaml, updating pubspec.lock with Flutter dependency resolution. No tests have been executed at planning time.

## Mandatory host runners

- `bash test_driver/verify_android_orientation.sh MODE DEVICE CLASS`
- `bash test_driver/verify_ios_orientation.sh MODE DEVICE CLASS` on a macOS runner.
- `bash test_driver/verify_orientation_matrix.sh MODE` aggregates required receipts; MODE is `probe`, `layout` or `lock`.

All runners fail nonzero for missing SDK, device, fixture, unsupported enforcement, missing receipt or failed assertions. Use exit 2 for unavailable prerequisites and exit 1 for observed behavior failures; both block acceptance. Never represent missing platforms as passing/skipped coverage.

## Required classes and command set

Android variables: `ANDROID_PHONE`, `ANDROID_TABLET_PRE16`, `ANDROID_TABLET_16_LARGE`. The runner must query SDK and logical smallest display width to reject a mislabeled device; the last class requires Android 16+ and smallest width ≥600dp, with an API-36-targeted app.

iOS variables: `IOS_PHONE`, `IOS_TABLET`, on the supported macOS/Xcode host.

```bash
bash test_driver/verify_android_orientation.sh "$MODE" "$ANDROID_PHONE" android-phone
bash test_driver/verify_android_orientation.sh "$MODE" "$ANDROID_TABLET_PRE16" android-tablet-pre16
bash test_driver/verify_android_orientation.sh "$MODE" "$ANDROID_TABLET_16_LARGE" android-tablet-16-large
# Separate macOS job; no Android --flavor alpha arguments:
bash test_driver/verify_ios_orientation.sh "$MODE" "$IOS_PHONE" ios-phone
bash test_driver/verify_ios_orientation.sh "$MODE" "$IOS_TABLET" ios-tablet
```

The aggregator consumes all five per-mode receipts from `specs/verifications/e01/native/`, whether produced locally or copied from the macOS job. It validates matching source revision, build mode, scenario set and device class. `layout` requires tablet rotation plus phone no-regression evidence; `probe`/`lock` require all five. It cannot return 0 merely because a directory contains arbitrary JSON.

## Fixture and host protocol

Use an isolated app/test profile with a deterministic local chat, draft and attachment. No live messaging/auth credentials. The fixture exposes deterministic checkpoints and assertions through the native test harness, including currently visible pane, active chat GUID, text/attachment/reply draft, setting value and view orientation. Host runner records OS orientation separately; a widget's portrait MediaQuery alone is not proof of native locking.

Android runner builds/installs alpha/debug test app, identifies its actual package from the built manifest, and drives host rotation with ADB/emulator mechanisms supported by the selected isolated device. Snapshot and restore device rotation settings in an exit trap; do not modify the user's normal device without consent. Run full-screen and applicable freeform probes, recording whether the manifest's landscape window hint affects startup. Non-applicable freeform coverage must be explicitly recorded with evidence and must not substitute for full-screen tests.

iOS runner drives supported simulator/XCTest orientation controls and app termination/launch through Xcode tooling. If physical-device rotation automation is unavailable, that device entry is blocked; a separate available simulator can establish coverage but cannot be mislabeled as physical-device proof. iPad OS multitasking behavior must be included, not replaced with an unauthorized full-screen opt-out.

For `layout`, exercise OS portrait/landscape both directions three times with draft; inspect chat, Back, widths, keyboard and settings routes. For `probe`, request allowed orientations through a test-only Flutter channel probe, observe actual OS result and record Android compatibility/iPad multitasking constraints without modifying production policy. For `lock`, toggle through real app settings, wait for the durable-save acknowledgment, immediately force-stop/terminate the process, relaunch without clearing app data, and assert saved setting plus native portrait orientation. Then disable and verify device-controlled rotation; repeat with upside-down preference preserved.

Process relaunch requires a host-controlled test fixture protocol capable of reconnecting after process death. It is mandatory, not optional integration-runner behavior. Restore app/device test state in cleanup and fail if the test accidentally clears persisted settings before asserting restart behavior.

## Receipts

Each class/mode emits machine-readable JSON with source commit/worktree digest, platform/SDK, device ID/class/display dimensions, target SDK where relevant, tool versions, mode, scenarios and per-scenario pass/fail/blocked, OS and Flutter orientation observations, process IDs before/after restart, saved-setting observation, and screenshot/log paths. Failed or missing required scenarios block the aggregator. Capture screenshots without user message data.

`test/harness/orientation_fixture_test.dart` covers deterministic fixture lifecycle, receipt validation (including missing/stale/mislabeled entries) and protocol logic. Passing that test proves the harness logic, not native behavior. Only the full matrix commands prove native acceptance.

## Current blockers

Flutter/Dart/ADB are absent from PATH, native submodules are uninitialized, and no native devices/macOS runner are evidenced. Android 16 large-screen and iPad orientation enforcement require a concrete platform decision if probes cannot meet the approved universal lock. Browser/Playwright testing cannot substitute for this native contract.
