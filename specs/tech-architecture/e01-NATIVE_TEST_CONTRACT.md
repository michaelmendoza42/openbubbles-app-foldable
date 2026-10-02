# e01 Android native verification contract

## Scope

This contract is Android-only. iOS/iPad receipts and runners are not e01 gates
for this validation run. The required Android device classes are:

- `android-phone`: Android API 36+ and smallest display width below 600dp.
- `android-tablet-pre16`: Android API below 36 and smallest display width at
  least 600dp.
- `android-tablet-16-large`: Android API 36+ and smallest display width at
  least 600dp, with the app targeting API 36.

## Runner and command

The implemented runner is lifecycle-managed and serial: it starts exactly one
isolated foreground emulator, waits for WindowManager, restores its initial
rotation state, and verifies shutdown. It must not be wrapped in `nohup` or a
detached launcher.

```bash
bash test_driver/verify_android_orientation.sh lock \
  openbubbles_phone_api36 android-phone
bash test_driver/verify_android_orientation.sh lock \
  openbubbles_tablet_api35 android-tablet-pre16
bash test_driver/verify_android_orientation.sh lock \
  openbubbles_tablet_api36 android-tablet-16-large
```

Source `test_driver/android-env.sh` first and add the approved Rust/protoc
paths. The runner rejects mismatched AVD names, SDKs, and smallest-width
classes. It emits a fresh JSON receipt, logs, and screenshots under
`$E01_ANDROID_EVIDENCE_ROOT` (default:
`~/.cache/openbubbles-android-validation`).

## Fixture protocol

`integration_test/android_orientation_lock_test.dart` initializes no account,
network transport, contact, or live message data. It uses real Android
SharedPreferences, production `SettingsService`, `SystemChrome`, and the
reusable production `SettingsSwitch` control. At deterministic checkpoints the
host requests physical landscape through ADB WindowManager controls.

For `lock`, the fixture saves the enabled preference, requests the production
policy, and reports the Flutter viewport. The host captures an OS screenshot,
force-stops the alpha fixture package, and confirms the PID is absent. A fresh
Flutter integration launch (`relaunch`) loads the saved preference, reapplies
the policy, reports its new process PID and viewport, then disables the lock
and verifies device-controlled landscape.

The receipt records physical display dimensions and Flutter viewport separately
to distinguish enforced portrait from letterboxing. The alpha/debug test build
uses ignored CI FairPlay placeholders and is never a production or upgrade
artifact.

## Result semantics

Phone and pre-16 tablet lock/relaunch/unlock observations must all pass for a
passing receipt. Android-16 large-screen refusal is emitted as
`measured-failure-android16-large-screen` and exits nonzero: it records actual
platform behavior but never satisfies universal portrait-lock acceptance.
Missing prerequisites, a bad fixture checkpoint, failure to restore rotation,
or failure to stop the emulator are failures, not skips.

The Android 16 large-screen result is expected to be evaluated against the
Android compatibility limitation without adding an unauthorized manifest opt-
out, target-SDK downgrade, signing change, or global device-setting change.
