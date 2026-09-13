# Portrait features — implementation evidence

## Status: implemented; full release acceptance remains blocked

Version remains `1.15.0+228` (Android `20002228`). No production signing, package identity, Android compatibility opt-out, iPad multitasking restriction or target-SDK change was made.

## Changed behavior

- Mobile portrait/square windows use one pane; qualifying landscape retains the tablet split. All layout/routing predicates use the shared policy, preserving desktop/web and bubble exclusions.
- Both pane navigators remain mounted. Portrait visibility follows active routes, including new-chat/non-chat routes, rather than only an active Chat model. Navigation and Back operate on the same route owner across orientations.
- Settings details retain their nested route and remain visible when rotating to portrait.
- Misc settings offers a phone/tablet “Lock to portrait” switch. The new preference defaults false, round-trips in both deserializers, and saves durably before applying the common foreground-mobile policy. Restore/import awaits saving before policy application/success.
- Lock requests upright portrait only; unlock restores existing rotation choices and retained upside-down preference. No OS-wide user setting is changed by production code.

## Host proof

`source test_driver/android-env.sh && flutter test --no-pub test/layout test/settings test/environment --reporter expanded`

Focused suite passes 18 tests after review corrections (latest host output: `~/.cache/openbubbles-android-setup/portrait-back-focus-tests2.log`). Tests cover policy thresholds, stable nested route ownership, repeated size transitions and text draft, pane width caches, direct shared Back/system dispatch, settings persistence/restore and headless suppression. They are not a complete data-backed chat test suite; reply/attachment draft and complete production-controller lifecycle remain acceptance gaps.

Analyzer: changed files report existing deprecated/unused-import diagnostics, with no new compile errors identified. The new native test entrypoint separately analyzed cleanly. No unrelated warning cleanup was undertaken.

## Android build and native runtime proof

Build environment includes Flutter 3.24.0, Java 21, Rust stable 1.98.1, protoc 28.3 and Android NDK. Initial Rust failure was 20 missing FairPlay fixture files. Copying the repository CI's documented placeholders into ignored paths resolved that build blocker. These are TEST INPUTS, not release credentials; do not distribute this test build as a normal upgrade.

The native integration build succeeded and installed on `openbubbles_tablet_api36`:

```text
flutter test --no-pub integration_test/tablet_portrait_test.dart -d emulator-5554 --flavor alpha --reporter expanded
E01_ROTATE_PORTRAIT
E01_ROTATE_LANDSCAPE
E01_ROTATE_PORTRAIT
E01_ROTATE_LANDSCAPE
E01_ROTATE_PORTRAIT
E01_CAPTURE_PORTRAIT
E01_NATIVE_LAYOUT_PASSED
00:13 +1: All tests passed!
```

The host controller simultaneously ran:

```bash
python3 test_driver/tablet_rotation_probe.py \
  --test-log /home/michael/.cache/openbubbles-android-setup/native-portrait-test4.log \
  --output /home/michael/.cache/openbubbles-android-setup/native-feature-proof-4
```

Result: expected OS rotation sequence passed; device rotation setting restored. The integration fixture uses production TabletModeWrapper, NavigatorService, layout policy and real Android SharedPreferences, with a synthetic local text-draft pane. No Apple account, real contacts or messages were involved. It verifies actual native display changes, full portrait pane width, draft continuity, route Back and preference reload. It does **not** verify the whole ConversationList UI, attachment/reply drafts, process restart, actual settings-toggle UI or enforcement of an app-requested portrait lock.

Run the emulator in one foreground terminal, controller in a second, integration test in a third. Use a fresh output directory and fresh test-log filename for every invocation. This narrow probe is not the planned full five-device matrix runner.

## Artifacts

- Native Flutter output: `~/.cache/openbubbles-android-setup/native-portrait-test4.log`
- Host receipt: `~/.cache/openbubbles-android-setup/native-feature-proof-4/result.json`
- Screenshot: `~/.cache/openbubbles-android-setup/native-feature-proof-4/native-fixture-portrait.png` (1600×2560; same fixture as the visually inspected prior run)
- APK build output: `~/.cache/openbubbles-android-setup/portrait-apk-fixture-build.log`
- Earlier full app onboarding: `~/.cache/openbubbles-android-setup/app-runtime/startup-portrait.png` (filename is historical; actual image was landscape)

The last `build/app/outputs/flutter-apk/app-alpha-debug.apk` is the integration-test entrypoint, NOT the normal app entrypoint. Do not use it as an upgrade APK. Building a deliverable also requires matching the user's installed package/signing identity and appropriate production inputs.

Playwright: not used — native Flutter/Android OS behavior requires Flutter/ADB, not browser emulation.

## Issues corrected before handoff

Independent reviews caught portrait-origin root-vs-nested route mismatch, disappearing settings details, hidden non-chat right routes, conditional left navigator destruction, orientation-gated Back, competing PopScopes, and fire-and-forget restore persistence. These were corrected with expanded tests. A final review also caught direct Back bypassing route-local PopScope, hidden underlying root routes receiving Back, and focus retained by an offstage pane. Back now uses scoped maybePop (including initial-route selection handlers), root callbacks disable recursive fallback, and hidden panes exclude focus. Four additional host regressions pass for those cases; the final native rerun uses the shared Back method and passes. Ticker suppression was tried then removed because it stalled outgoing route disposal.

Native test attempts initially failed because its host logcat coordination stalled, then because mock TestTextInput.hide is invalid in a native binding. The controller now consumes the Flutter test log, and the fixture unfocuses the actual field. The final native rerun passed. Host runner records cleanup failure rather than claiming success.

## Remaining gates

- Android 16 large screens may ignore app orientation requests; iPad enforcement depends on multitasking restrictions. No unauthorized opt-out was added. See `native-limitations.md`.
- Native phone/pre-16-tablet/iOS matrix, genuine process-restart proof and account-backed complete chat/reply/attachment validation remain unexecuted.
- Required broad host runners in the original plan are not implemented; the narrow native probe is complementary evidence, not a replacement claimed as complete.
- Cargo changed `rust/Cargo.lock` while resolving the checked-out stub submodules for the test build; this unrelated generated change is excluded from the feature commit.
