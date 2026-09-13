# e01s02 — Persisted phone/tablet portrait lock

## 1. Business narrative

Users can choose to keep the app upright in portrait instead of following device rotation. The preference must work on phones and tablets and survive restart.

## 2. Actors

Phone and tablet users. Universal refers to both form factors, not desktop window orientation.

## 3. Scope and maturity

Maturity: 3 (countable). Type: feat. BCP: 4. Risk: P1. Requirements R3/R4. Depends on e01s01 for correct portrait tablet presentation.

## 4. Current behavior

SettingsService startup and the Misc panel's Android upside-down switch duplicate the same orientation list. The Settings model persists `allowUpsideDownRotation` but has no portrait-lock key. iPad enforcement and Android-16 large-screen enforcement introduce a real platform gate; see §19.

## 5. Main flow

Open Misc settings on a phone or tablet, enable “Lock to portrait”; the app becomes portrait and stays there when rotated. Restart: the preference is still enabled. Disable: normal device-controlled orientation returns.

## 6. Alternative flows

Old preferences without a key default false. Lock wins over upside-down rotation, without erasing the existing upside-down preference. Toggling upside-down while locked cannot re-enable landscape; unlock reapplies the retained preference. No orientation calls in web/desktop or headless initialization.

## 7. Requirements

### ADDED: R3 — Universal portrait lock

Provide a persisted, off-by-default “Lock to portrait” toggle for phones/tablets. Enabled means upright portrait only; startup and live changes use the same policy.

### MODIFIED: R4 — Orientation policy application

**Before:** Startup and upside-down callback independently apply an allowed orientation list.

**After:** Both use a shared policy honoring portrait lock. With lock disabled, existing user-controlled rotation behavior and upside-down preference are preserved.

## 8. Responsibilities and callers

`Settings` owns serialized defaults; `SettingsService` applies loaded preferences and runtime changes; Misc panel exposes controls. StartupTasks calls SettingsService in foreground and headless contexts. A UI-only orientation change must not leak platform calls into background sync.

## 9. Implementation approach

Add `lockToPortrait = false.obs`, serialize under `lockToPortrait` and load missing values as false in both `Settings.fromMap` and `Settings.updateFromMap` (restore/import). Add one policy/application seam in SettingsService, invoked only on supported foreground mobile paths after load and on relevant toggle changes. Reason for depth: startup and both controls must compute the same orientation list, with channel behavior testable without launching RustPush.

Enabled policy: `[DeviceOrientation.portraitUp]`. Disabled: preserve `[landscapeRight, landscapeLeft, portraitUp]` plus optional `portraitDown`, which Flutter maps to Android user/fullUser modes. Await the channel request where lifecycle allows; avoid racing stale toggle applications.

Place toggle near the existing rotation setting in `lib/app/layouts/settings/pages/misc/misc_panel.dart`, visible on phones/tablets, not desktop/web. Follow existing row/switch presentation, with no redesign. Await `settings.saveOne('lockToPortrait')` (or the existing `saveAsync` seam when restoring all preferences) before reporting toggle completion, then apply/converge orientation policy. Do not use the fire-and-forget `saveSettings`/`Settings.save` path for this preference: its async forEach does not prove durable completion. Test immediate termination after acknowledged save. Keep the existing Android-only upside-down setting's scope unless platform evidence requires a separately reviewed change.

## 10. Expected files

- `lib/database/global/settings.dart`
- `lib/services/backend/settings/settings_service.dart`
- `lib/app/layouts/settings/pages/misc/misc_panel.dart`
- `test/settings/portrait_lock_test.dart`
- `integration_test/portrait_lock_test.dart`
- `pubspec.yaml` / `pubspec.lock` for the SDK integration-test harness.
- Planned host runners and fixture protocol in `../../tech-architecture/e01-NATIVE_TEST_CONTRACT.md`.
- Android MainActivity manifest only if a tested, explicitly approved compatibility policy is necessary. No automatic iPad full-screen opt-out.

## 11. Dependencies and API evidence

[OK] Existing Flutter services API, SharedPreferences, GetX, `flutter_test`; [OK] SDK `integration_test` as dev-only harness. No new production package.

Official signature: `Future<void> SystemChrome.setPreferredOrientations(List<DeviceOrientation> orientations)`. Empty list defers to OS defaults, but the existing nonempty user/fullUser policy preserves the current upside-down preference. Source: https://api.flutter.dev/flutter/services/SystemChrome/setPreferredOrientations.html

## 12. Data and compatibility

Additive preference only; no ObjectBox schema migration. Round-trip false/true/missing key, retain tabletMode/upside-down values, verify a newly constructed SettingsService reloads persisted state. Mock SharedPreferences only in tests.

## 13. Failure handling

An OS ignoring an orientation request is not success. Capture actual orientation after toggle/rotation/restart on each supported device class. Do not fake portrait by rotating the widget tree, disable device auto-rotate globally, lower target SDK or alter unrelated OS multitasking to make the test pass.

## 14. Implementation steps

Verification commands target tests to be added during execution. Start RED, end GREEN; no passing ledger entries at planning time.

1. After e01s01's harness bootstrap, establish native feasibility on the full mandatory matrix → verify: `bash test_driver/verify_orientation_matrix.sh probe`
2. Implement setting persistence, centralized policy, startup/control integration and unit/widget tests → verify: `flutter test test/settings/portrait_lock_test.dart`
3. Run host-driven enable/disable/restart checks across the required native matrix → verify: `bash test_driver/verify_orientation_matrix.sh lock`

The mandatory host runners and per-platform variables are specified in `../../tech-architecture/e01-NATIVE_TEST_CONTRACT.md`. They must drive OS rotation and process termination/relaunch, not merely rebuild widgets. Missing required entries block the matrix. Probe mode reports unsupported enforcement as failure rather than skipping it. An iOS/macOS job runs separately without Android flavor arguments; the aggregator requires its receipt.

## 15. Test matrix

Missing-key/false/true serialization; policy with upside-down true/false; mocked SystemChannels.platform requests at foreground startup and control changes; no headless/web/desktop calls; switch visibility and immediate save; rapid toggles converge to final choice.

Native: Android phone, pre-16 tablet, API-36-targeted Android 16 tablet with smallest width ≥600dp; iPhone and iPad on an available supported runner. Lock on/off; auto-rotate on/off; restart; keep selected conversation/draft when lock forces landscape→portrait. Test OS overrides/multi-window and document limitations rather than claiming universal enforcement from a phone-only pass.

## 16. Verification script

Use isolated fixtures, not live account actions. Confirm OS auto-rotate, enable lock in landscape, inspect upright portrait, rotate device both ways, stop/relaunch app, verify persisted toggle and portrait, then disable and verify normal rotation. Repeat with upside-down setting enabled. Save device details, channel logs, screenshots and test output under `specs/verifications/e01/`. Native integration replaces Playwright because browser emulation cannot prove mobile OS orientation policy.

## 17. Acceptance criteria

- Given a phone or tablet with no saved lock key, when starting, then lock defaults off and normal device rotation remains.
- Given lock enabled, when physically rotated, then the app remains upright portrait.
- Given a saved enabled lock, when the app restarts, then lock is still enabled and applied.
- Given upside-down enabled and lock enabled, when rotation settings are applied, then portraitUp alone is requested and the upside-down preference remains saved.
- Given lock disabled again, then the device's auto-rotate setting controls normal behavior.
- Given native enforcement is unavailable for a required platform, then this story remains blocked rather than being marked complete with a silent best-effort implementation.

## 18. Out of scope

Desktop/web rotation settings, widget-tree rotation simulation, target-SDK downgrade, OS multi-window removal without explicit approval and unrelated settings cleanup.

## 19. Risks and native decision gate

The local app targets Android API 36. Official docs say Android 16 ignores orientation restrictions for large screens (smallest width ≥600dp); an activity-level `android.window.PROPERTY_COMPAT_ALLOW_RESTRICTED_RESIZABILITY` opt-out is documented as temporary. Native feasibility work must test whether this is a viable supported option and record its tradeoff before proposing a manifest change.

Flutter states iPad honors preferred orientations only when multitasking is disabled. Current Info.plist does not declare `UIRequiresFullScreen`. Removing OS Split View is not authorized by the user's request for no in-app split pane. If that is required, present the concrete choice between platform support tradeoffs and scope adjustment before implementing it. Do not reopen already-settled phone/tablet scope as a routine preference question.

Sources: Flutter API above; https://developer.android.com/about/versions/16/behavior-changes-16#ignore-orientation . Flutter/Dart/ADB, native submodules and devices are currently unavailable; this gate cannot yet be demonstrated locally.

## 20. Evidence and handoff

All tasks start failing. The requirement is confirmed; universal native feasibility is not. Complete the executable probe and resolve the real platform tradeoff before marking e01s02 ready for implementation on affected platforms. Do not claim a universal lock based solely on a mocked channel call.
