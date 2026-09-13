# e01s01 — Single-pane tablet portrait

## 1. Business narrative

A tablet user wants a wider phone-style portrait screen, while retaining the existing landscape tablet layout. Rotation must not close the conversation or discard its draft.

## 2. Actors

Phone/tablet app users; existing desktop/web users are regression-only actors.

## 3. Scope and maturity

Maturity: 3 (countable). Type: fix. BCP: 4. Risk: P1, with P0 state-loss tests. Requirements R1/R2 in `../../product/SCOPE_LATEST.yaml`.

## 4. Current behavior and evidence

`SettingsService.init` already allows portrait. The layout predicates lack a mobile landscape requirement. `TabletModeWrapper.build` explicitly closes the active chat on split exit and renders only its left child. This explains layout/state defects in source; the user's specific device behavior has not been reproduced.

## 5. Main flow

Open a conversation on a landscape tablet; type an unsent draft; rotate to portrait. The same chat fills the screen, with no conversation-list pane beside it. Rotate back: the list and same chat occupy the existing landscape split. Back in portrait returns to the list.

## 6. Alternative flows

Rotate with no chat selected, with settings/details open, keyboard visible, reply/attachment drafts, or rapid repeated orientation changes. Tablet mode off remains single-pane. Bubble and desktop/web behavior remain unchanged. Square mobile windows use single-pane; existing landscape width threshold remains >600 logical pixels.

## 7. Requirements

### MODIFIED: R1 — Tablet layout selection

**Before:** Width/aspect/phone-class heuristics can select split layout in tablet portrait.

**After:** Mobile portrait is single-pane; qualifying mobile landscape retains the existing split layout and thresholds. Existing desktop/web predicates remain unchanged.

### MODIFIED: R2 — Conversation continuity

**Before:** Exiting split layout closes the active conversation, while the right navigator disappears.

**After:** Mode transition preserves selected chat, visible conversation, draft and sensible Back behavior without duplicate controllers/routes.

## 8. Module responsibilities and callers

Use `../../IMPACT_LATEST.md` for the module/caller/contract table. Theme helpers and NavigatorService must agree. TabletModeWrapper owns pane presentation; ConversationList supplies navigators. ConversationView/TextField own controller/draft lifecycle.

## 9. Proposed implementation boundary

Share one small layout eligibility calculation between `showAltLayout`, contextless lookup and `NavigatorService.isTabletMode`; preserve existing desktop/web/bubble distinctions at adapters. Reason for depth: it prevents rendering, route destination and width calculations from disagreeing during orientation changes and is testable without account/native startup.

Keep nested navigator identities stable when changing pane visibility. Prefer preserving the existing right navigator and presenting it full-width for an active portrait conversation, with the list retained offstage. Do not just remove the close call and return the left pane. Verify focus/tickers/offstage behavior and Back routing. If existing root-stack routes must be transferred, perform an explicit post-frame, idempotent handoff—not a navigation mutation during build. Select the minimal strategy only after inspecting the full route/controller lifecycle and proving both directions in a widget harness.

Recalculate/reset split width caches so a hidden nested navigator does not retain half-width portrait content. Preserve draft text, annotations, attachments and reply selection with the existing Chat-backed ownership; avoid database migrations or unrelated model changes.

## 10. Expected files

- `lib/helpers/ui/theme_helpers.dart`
- `lib/services/ui/navigator/navigator_service.dart`
- `lib/app/wrappers/tablet_mode_wrapper.dart`
- `lib/app/layouts/conversation_list/pages/conversation_list.dart`
- SettingsPage integration only if required by the shared wrapper contract.
- New tests: `test/layout/tablet_layout_policy_test.dart`, `test/layout/tablet_navigation_test.dart`, `integration_test/tablet_portrait_test.dart`.
- `pubspec.yaml` / `pubspec.lock`: declare SDK integration_test before native testing.
- `test_driver/verify_android_orientation.sh`, `test_driver/verify_ios_orientation.sh`, `test_driver/verify_orientation_matrix.sh`: mandatory planned host runners; see `../../tech-architecture/e01-NATIVE_TEST_CONTRACT.md`.

## 11. Dependencies

[OK] Existing Flutter framework, GetX and `flutter_test`. [OK] SDK `integration_test` for native regression harness if added as a dev dependency; no new production packages. No Rust/account API changes. Restore the existing native build environment before device tests.

## 12. State contracts

One active chat identity; no draft loss or duplicated route push on repeated rebuild; portrait shows one interactive pane; landscape divider preferences preserved. Do not send real messages in tests.

## 13. Failure handling

Capture pre-change failure before changing policy. If native dependencies prevent full startup, use an injected deterministic local chat fixture for widget tests and record native evidence as blocked, not passing. Never mark rotation proof complete from source inspection alone.

## 14. Implementation steps

Commands below target tests created by their steps. They are not expected to pass in this planning-only checkout. Capture an initial RED result, then satisfy the listed GREEN command before marking a task passing.

0. Bootstrap SDK integration_test and host-driven isolated fixtures per the native test contract → verify: `flutter pub get && flutter test test/harness/orientation_fixture_test.dart`
1. Add matrix tests and align the three eligibility entry points → verify: `flutter test test/layout/tablet_layout_policy_test.dart`
2. Add stable navigator/pane transitions, width reset and state-preservation tests → verify: `flutter test test/layout/tablet_navigation_test.dart`
3. Run host-driven tablet rotation acceptance on the required native matrix → verify: `bash test_driver/verify_orientation_matrix.sh layout`

## 15. Test scenarios

Policy: 800×1280 and 1024×1366 portrait; reversed landscape; 600/601 width threshold; square; tablet mode off; bubble; desktop/web unchanged. Use full view dimensions, not a narrowed pane or keyboard-reduced constraint.

Navigation: both directions, no active chat, active chat, text/reply/attachment draft, Back, settings/details routes, keyboard open and three repeated rotations. Assert chat GUID, draft contents, pane visibility, controller count and full portrait width. Native test must observe an actual orientation change, not merely mock MediaQuery. Keep the OS test rotation setting restored after each run.

## 16. Verification script

On an isolated tablet fixture with auto-rotate enabled and lock off: open chat, enter draft/add a local attachment, rotate landscape→portrait→landscape three times, check continuity and Back. Repeat from list-only and settings. Save screenshots and logs under `specs/verifications/e01/`. Native Flutter integration is the appropriate harness; Playwright cannot prove OS orientation or native Flutter routing here. Desktop/web remain unchanged and require no newly designed browser surface.

## 17. Acceptance criteria

- Given tablet mode enabled and a portrait tablet, when the app renders, then only one full-width pane is visible.
- Given qualifying landscape tablet dimensions, when rendered, then the existing split layout remains.
- Given an active chat with draft text and attachment, when rotated in both directions, then the same chat and complete draft remain.
- Given an active portrait chat, when Back is pressed, then the conversation list appears without stale or duplicate routes.
- Given tablet mode off, bubble mode or desktop/web, when layout is reevaluated, then existing behavior outside the mobile portrait change is retained.

## 18. Out of scope

Portrait-lock setting (e01s02), platform multitasking opt-outs, messaging changes, cosmetic redesign and global device settings.

## 19. Risks and execution gates

Flutter/Dart/ADB are not on PATH and native submodules are uninitialized. Native validation is blocked until environment/device access exists. These are prerequisites, not failing application tests. P0 draft tests gate release even though the story's overall risk is P1. Rationalization rejected: removing the close call alone is not conversation preservation.

## 20. Evidence and handoff

Tasks begin failing, meaning acceptance is unmet, not that a test was run and failed. Record commands, exit codes, device/OS, screenshots and limitations under `specs/verifications/e01/` during execution. This planning artifact is not evidence of implemented behavior.
