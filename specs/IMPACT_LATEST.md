# Portrait behavior impact assessment

## Target and root-cause evidence

Startup already permits portrait in `SettingsService.init`; Android MainActivity has no fixed `screenOrientation`. The report of being stuck in landscape is not evidence of a hardcoded landscape OS lock.

The application manifest also declares `WindowManagerPreference:FreeformWindowOrientation = landscape` alongside a tablet freeform size hint. This is a separate candidate for freeform/windowing environments, not proof of a full-screen orientation lock. The native probe must compare full-screen and applicable freeform behavior before attributing the user's device issue entirely to Dart layout heuristics. Do not remove metadata until its actual platform behavior is reproduced.

There are three related layout decisions: `ThemeHelpers.showAltLayout`, `showAltLayoutContextless` in `lib/helpers/ui/theme_helpers.dart`, and `NavigatorService.isTabletMode` in `lib/services/ui/navigator/navigator_service.dart`. Their width/aspect heuristics permit split layout on large portrait tablets. `TabletModeWrapper.build` explicitly closes the active chat when leaving split mode. Merely changing a breakpoint or deleting that close is insufficient: the wrapper returns only its left child, and navigation currently owns the conversation on a different route stack.

## Modules, callers and contracts

| Module / purpose | Callers / dependents | Contract to preserve |
| --- | --- | --- |
| ThemeHelpers / layout eligibility | TabletModeWrapper, conversation list, message widgets, settings | Rendered panes, routing and available widths must agree; desktop/web and bubbles retain current behavior |
| NavigatorService / route and pane-width ownership | Conversation tiles, details/timeframe picker, settings, message interaction UI | Back returns to list; no duplicate chat controller, stale nested route or width after rotation |
| TabletModeWrapper / split rendering | ConversationList and SettingsPage | Active pane remains visible and state survives mode changes; retain landscape divider behavior |
| Settings model / persisted preferences | SettingsService and settings panels | Missing key defaults false; existing upside-down preference round-trips unchanged |
| SettingsService / initialization and updates | StartupTasks; settings callbacks | One mobile orientation policy, no headless/platform-channel calls from background contexts |
| ConversationView/TextField / controller and draft ownership | ConversationList/navigator routes | Chat identity, text, annotations, attachments and reply state survive transition; disposal must not erase replacement state |

## Dependents (9 files in layout-symbol inventory)

- `lib/app/layouts/settings/settings_page.dart`
- `lib/services/ui/navigator/navigator_service.dart`
- `lib/app/layouts/conversation_details/dialogs/timeframe_picker.dart`
- `lib/app/wrappers/tablet_mode_wrapper.dart`
- `lib/app/layouts/conversation_view/widgets/message/message_holder.dart`
- `lib/app/layouts/conversation_list/pages/conversation_list.dart`
- `lib/helpers/ui/theme_helpers.dart`
- `lib/app/layouts/conversation_view/widgets/message/interactive/interactive_holder.dart`
- `lib/app/layouts/conversation_list/widgets/tile/conversation_tile.dart`

Inventory command: `rg -l 'showAltLayout|isTabletMode' lib --glob '*.dart'`. These are direct textual references, not a complete semantic dependency graph.

Additional touched seams: `lib/database/global/settings.dart`, `lib/services/backend/settings/settings_service.dart`, `lib/app/layouts/settings/pages/misc/misc_panel.dart`; conditional native platform policy work only after feasibility evidence.

## Affected stories

- e01s01: portrait single-pane layout and state-preserving rotation.
- e01s02: persisted universal portrait lock.

## Test coverage

No existing scenario tests were found for these seams; `test_driver/integration_test.dart` is just a driver. `flutter_test` is declared, but Flutter/Dart/ADB are not on PATH, native submodules are uninitialized, and no test device is available in current evidence. Test commands in the capsule are implementation targets, not completed verification.

## Risk: High

Shared routing/layout decisions have no identified regression coverage, and an incorrect transition can lose user draft state. Chosen mode: Standard for planning, because scope is clear and the documents are reversible. The implementation has shared navigation/state risk and requires staged tests. An approved native multitasking/manifest support-policy change escalates that affected phase to High-risk with an explicit decision gate. A localized flag change with existing regression coverage would have allowed Fast. Changing target SDK or authentication to obtain a fixture is not authorized by this feature.

## Native feasibility gate

Flutter's `SystemChrome.setPreferredOrientations(List<DeviceOrientation>)` sends a platform-channel request. The approved lock maps to `[portraitUp]`; unlock restores the existing user-oriented list and upside-down preference.

Official Flutter docs state API-36-targeting apps on Android 16 large screens cannot normally force orientation. This app targets 36. Android documents a temporary activity-level `android.window.PROPERTY_COMPAT_ALLOW_RESTRICTED_RESIZABILITY` opt-out. Treat that as a candidate to test, not a guaranteed universal fix or authorization to weaken platform support.

Flutter also states iPad enforcement requires multitasking disabled. `ios/Runner/Info.plist` advertises all iPad orientations and contains no `UIRequiresFullScreen` key. No in-app split pane does not mean disabling OS Split View. Do not silently do so: record native results and resolve the product tradeoff before accepting e01s02.

Sources:
- https://api.flutter.dev/flutter/services/SystemChrome/setPreferredOrientations.html
- https://developer.android.com/about/versions/16/behavior-changes-16#ignore-orientation

## Recommended action

Add deterministic layout/navigation/draft tests first, then implement e01s01. Establish native toolchain/device proof and resolve platform policy for e01s02 before claiming the universal lock works. No application files were changed during this assessment.
