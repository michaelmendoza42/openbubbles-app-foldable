# Portrait features — implementation evidence

## Status: implemented; Android large-tablet acceptance remains blocked

Version remains `1.15.0+228` (Android `20002228`). No production signing,
package identity, Android compatibility opt-out, target-SDK change, or iPad
multitasking restriction was made.

## Changed behavior

- Mobile portrait/square windows use one pane; qualifying landscape retains the
  tablet split. All layout/routing predicates use the shared policy, preserving
  desktop/web and bubble exclusions.
- Both pane navigators remain mounted. Portrait visibility follows active
  routes, including new-chat/non-chat routes, rather than only an active Chat
  model. Navigation and Back operate on the same route owner across
  orientations.
- Settings details retain their nested route and remain visible when rotating
  to portrait.
- Misc settings offers a phone/tablet “Lock to portrait” switch. The preference
  defaults false, round-trips in both deserializers, and saves durably before
  applying the common foreground-mobile policy. Restore/import awaits saving
  before policy application/success.
- Lock requests upright portrait only; unlock restores existing rotation
  choices and retained upside-down preference. No OS-wide user setting is
  changed by production code.

## Host proof

```bash
source test_driver/android-env.sh
flutter test --no-pub test/layout test/settings test/environment --reporter expanded
```

The focused suite passed 18 tests in the prior implementation run. The current
lock-focused rerun also passed:

```text
flutter test --no-pub test/settings/portrait_lock_test.dart --reporter expanded
00:00 +5: All tests passed!
```

These tests cover policy thresholds, stable nested route ownership, repeated
size transitions and text draft, pane width caches, direct shared Back/system
dispatch, settings persistence/restore, and headless suppression. They are not
a complete data-backed chat suite.

## Android native runtime proof

`test_driver/verify_android_orientation.sh` is a lifecycle-managed, serial
Android runner. It starts an isolated foreground AVD, records SDK/display dp,
uses the alpha/debug fixture build, forces physical WindowManager rotation,
force-stops after a durable lock save, launches a fresh native test process,
and records the Flutter viewport independently from the physical screenshot.
It restores the original rotation mode and verifies emulator shutdown.

```bash
E01_ANDROID_EVIDENCE_ROOT="$HOME/.cache/openbubbles-android-validation" \
  bash test_driver/verify_android_orientation.sh lock \
  openbubbles_phone_api36 android-phone

E01_ANDROID_EVIDENCE_ROOT="$HOME/.cache/openbubbles-android-validation" \
  bash test_driver/verify_android_orientation.sh lock \
  openbubbles_tablet_api35 android-tablet-pre16

E01_ANDROID_EVIDENCE_ROOT="$HOME/.cache/openbubbles-android-validation" \
  bash test_driver/verify_android_orientation.sh lock \
  openbubbles_tablet_api36 android-tablet-16-large
```

Results at source `163fb5aba5b31990658f07bd4b44539e66062702`:

- Phone/API36 (411.4dp): passed — lock remained `411×914` through force-stop
  and fresh launch; unlock returned to `914×411` after a host landscape
  request.
- Tablet/API35 (800dp): passed — lock remained `600×800` through force-stop
  and fresh launch; unlock returned to `1280×800`.
- Tablet/API36 (800dp): **measured failure** — lock stayed `1280×800`
  landscape before and after force-stop/relaunch. The command correctly exited
  nonzero and the receipt is not a pass.

The Android-16 receipt distinguishes display and app viewport: both were
landscape, ruling out a portrait letterbox interpretation. See
[native-limitations.md](native-limitations.md) for receipt/screenshot/log paths
and the fixture boundary.

The fixture uses real Android SharedPreferences, production `SettingsService`,
`SystemChrome`, and the reusable production `SettingsSwitch`; it has no Apple
account, messages, contacts, credentials, or network. Direct isolated
`MiscPanel` rendering was attempted but requires initialized production
navigation/theme state and failed with a non-finite Matrix4 transform. The
fixture is therefore precise callback/control proof, not a full settings-route
claim.

The alpha/debug APK is an integration-test entrypoint with ignored CI FairPlay
placeholder inputs. It is **not** a normal app entrypoint, production build, or
upgrade artifact.

## Remaining gates

- Android 16 large screens ignore the portrait request at target SDK 36 in the
  measured 800dp AVD. No unauthorized compatibility opt-out was added; this
  blocks a universal Android lock claim.
- The bounded fixture does not prove account-backed ConversationList UI,
  attachment/reply drafts, or the complete Misc settings route.
- This scope is Android-only; no iOS/iPad gate applies to this run.
- Native builds regenerated `rust/Cargo.lock`; that generated lockfile change
  is excluded from the validation edits.
