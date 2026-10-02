# e01 Android native orientation limitations

## Implemented policy

The application requests Flutter's supported mobile orientation policy only:

- **Lock to portrait on:** `DeviceOrientation.portraitUp`.
- **Lock to portrait off:** the existing landscape-left, landscape-right and
  portrait-up list, plus portrait-down when the existing Android-only setting
  is enabled.

The request is made only from foreground mobile startup and the two relevant
settings controls. Web, desktop and headless startup do not issue an
orientation platform-channel call. The lock preference is persisted before its
live policy request is applied.

## Android-only native matrix — 2026-09-14

All runs used source `163fb5aba5b31990658f07bd4b44539e66062702`, target SDK
36, and the alpha/debug integration fixture. These are test-only builds using
ignored CI FairPlay placeholders; they are **not** production or upgrade
artifacts. The host runner starts one foreground emulator at a time, restores
its original WindowManager rotation state, then verifies that it has stopped.

| Device/class | SDK / smallest width | Lock + force-stop/relaunch observation | Unlock observation | Result |
| --- | --- | --- | --- | --- |
| `openbubbles_phone_api36` / phone | 36 / 411.4dp | viewport remained portrait `411×914`; saved value was true after force-stop and fresh launch | host landscape request produced `914×411` | passed |
| `openbubbles_tablet_api35` / pre-16 large tablet | 35 / 800dp | viewport remained portrait `600×800`; saved value was true after force-stop and fresh launch | host landscape request produced `1280×800` | passed |
| `openbubbles_tablet_api36` / Android-16 large tablet | 36 / 800dp | viewport remained landscape `1280×800`, both before and after the fresh launch despite a portrait-only request | remained landscape `1280×800` | **measured failure** |

Receipts, physical-display screenshots, and per-phase Flutter logs are in:

- `~/.cache/openbubbles-android-validation/lock-android-phone-20260914T003019Z/`
- `~/.cache/openbubbles-android-validation/lock-android-tablet-pre16-20260914T001930Z/`
- `~/.cache/openbubbles-android-validation/lock-android-tablet-16-large-20260914T003504Z/`

Each receipt records the physical display metrics and Flutter viewport
separately. On Android 16 the physical display and viewport were both
landscape, so this is not a portrait letterbox being mistaken for enforcement.
The Android 16 command intentionally exits nonzero with
`measured-failure-android16-large-screen`; it is not a skipped or passing
result.

## Fixture boundary

The native fixture exercises `SettingsService`, real Android SharedPreferences,
`SystemChrome.setPreferredOrientations`, the reusable production
`SettingsSwitch`, and a host-issued `am force-stop` followed by a fresh Flutter
integration launch. It has no account, credentials, contacts, network
transport, or live messages.

It does **not** render the complete `MiscPanel`. Rendering that panel directly
in this isolated native environment requires initialized production
navigation/theme state and raised `Matrix4 entries must be finite` before the
switch could be observed. The fixture therefore proves the production
persistence/policy callback seam and switch control, not the full settings-page
route. This is explicitly narrower than a full app settings UI test.

## Platform decision and remaining gate

Android 16 with target SDK 36 ignores the app orientation request on the
measured 800dp large display. Android documentation describes that behavior
for displays with smallest width at least 600dp. No Android compatibility
opt-out, target-SDK change, manifest/signing change, or global device-setting
change was made. The tablet-API36 result blocks a universal Android portrait
lock claim.

This validation scope is Android-only. iOS/iPad execution is not an e01 gate
for this run. Account-backed conversation/attachment/reply-draft validation
also remains outside this bounded native fixture.
