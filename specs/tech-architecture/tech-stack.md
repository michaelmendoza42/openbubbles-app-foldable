# Project Context — OpenBubbles

Source snapshot: `eed1b6332efbb17adbf5ebfa2263ad770169f75e` on branch `rustpush`.
This is an observed architecture map, not a proposed redesign or a runtime certification.

## Stack

| Layer | Observed technology / constraint | Evidence |
| --- | --- | --- |
| App | Flutter; Dart `>=3.1.3 <4.0.0`; app `1.15.0+227`, package name `bluebubbles` | `pubspec.yaml` |
| State / service location | GetX `^4.6.6`, reactive values and globally accessible service instances | `pubspec.yaml`; `lib/services/network/socket_service.dart` |
| Native persistence | ObjectBox `^4.0.1`, generated bindings and entity models | `lib/database/database.dart`; `lib/database/models.dart` |
| HTTP / server events | Dio `^5.4.2+1`; Socket.IO client `^2.0.3+1`; Firebase Dart dependency | `pubspec.yaml`; `lib/services/network/` |
| Media | media_kit `^1.1.10+1`, audio/video/platform plugins | `pubspec.yaml` |
| Dart–Rust boundary | Flutter Rust Bridge pinned to `2.3.0` on both sides | `pubspec.yaml`; `rust/Cargo.toml`; `flutter_rust_bridge.yaml` |
| Native core | Rust edition 2021, `cdylib` / `staticlib`; Tokio, Serde, anyhow, Prost, UniFFI, vendored OpenSSL, AES-GCM | `rust/Cargo.toml` |
| Android | compile/target SDK 36, minimum 24, Java 21; multiple build flavors | `android/app/build.gradle` |
| CI toolchain | Flutter 3.24.0, stable Rust, Java 21, Protobuf compiler; Ubuntu debug APK build | `.github/workflows/build.yml` |

These are manifest constraints, not a claim about installed toolchain versions. Git-sourced dependencies include branch references (for example `audio_waveforms` at `main`) and an unpinned UniFFI manifest reference. Lockfiles must be considered when assessing actual dependency reproducibility; a floating manifest alone does not prove every build resolves new code.

`rustpush` and `telephony_plus` are external git submodules (`.gitmodules`). At inspection both directories were empty and `git submodule status` prefixed their recorded commits with `-` (uninitialized). `rust/Cargo.toml` also depends on `../rustpush/keystore`. Their implementation internals were not available for this map.

## Architecture

### Composition and source layout

This is a native-oriented Flutter client with an in-process Rust integration, not a conventional web frontend talking only to a REST server. Historical BlueBubbles naming and server-client machinery coexist with the OpenBubbles RustPush path.

- `lib/main.dart`: `main()` and Android bubble entry point `bubble()` call `initApp()`; root `Main` selects setup/splash/conversations and platform window behavior. `usingRustPush` is initialized to `true`.
- `lib/helpers/backend/startup_tasks.dart`: `StartupTasks.initStartupServices()` is the ordered composition root: Rust bridge → filesystem → logger → instance lock → settings → database → method channel/lifecycle/theme → contacts/notifications/intents.
- `lib/app/`: layouts, components, animation and wrapper UI code.
- `lib/services/`: backend, network, RustPush, UI and backend/UI-interoperation services. Services hold substantial domain orchestration and may directly interact with UI; this is not strict layer isolation.
- `lib/database/`: ObjectBox storage, generated code and model variants.
- `rust/src/api/api.rs`: handwritten native API implementation and rustpush re-exports.
- `lib/src/rust/`: generated bridge surface; generation mapping lives in `flutter_rust_bridge.yaml`.
- `rust_builder/`: Flutter native-plugin build glue, not the domain implementation.

After setup, `StartupTasks.onStartup()` initializes chat/socket services on non-desktop paths, fetches server details and registers FCM. This retained server startup machinery does **not** establish that all default messaging goes through HTTP or Socket.IO: the configured backend is RustPush, and SocketService returns early when its server address is empty.

### Backend and message flow

`lib/services/network/backend_service.dart` defines `BackendService` and selects `RustPushBackend()` as the global default. Its contract includes sends, edits, participants, typing/read operations and capability predicates. `HttpBackend` in `lib/services/network/http_service.dart` is a retained alternate implementation, not the selected default.

```text
Flutter UI / chat services
  → OutgoingQueue.queue / prepItem
  → ActionHandler.prepMessage (optimistic temporary local message)
  → queue dispatch → ActionHandler.sendMessage → BackendService
      → RustPushBackend → generated FRB API → native Rust / rustpush
      OR retained HttpBackend → Dio → server HTTP API
  → reconcile returned message with temporary GUID / persist and update UI

Android APNMsg method channel → recievedMsgPointer
  OR non-Android doPoll → recvWait
  → RustPushService.handleMsg / handleMsgInner
      → reflected chat messages / delivery-read receipts → IncomingItem
        → IncomingQueue → ActionHandler.handleNewMessage / handleUpdatedMessage
        → model persistence and reactive UI state
      → other push variants handled directly (e.g. account / FaceTime events)

Retained server events: SocketService → ActionHandler event dispatch
  → incoming queue / message reconciliation
```

Evidence: `lib/services/backend/action_handler.dart`, `lib/services/backend/queue/outgoing_queue.dart`, `lib/services/backend/queue/incoming_queue.dart`, `lib/services/backend/java_dart_interop/method_channel_service.dart`, and `lib/services/rustpush/rustpush_service.dart` (`RustPushBackend.sendMessage`, `sendMsg`, `RustPushService.handleMsg`, `handleMsgInner`). The RustPush service additionally handles attachments, sync, profile and other Apple-service operations. Backend capability checks matter: the alternate HTTP backend contains unsupported/no-op operations and cannot be assumed behaviorally interchangeable.

### Persistence and background execution

`Database.init()` skips ObjectBox on web. Native storage opens or attaches an ObjectBox store under the application documents directory; boxes include messages, chats, attachments, handles, contacts, scheduled messages, FCM data and themes. Database migration version is 5, with compatibility handling including the legacy `ThemeObject` entity (`lib/database/database.dart`).

Model-side persistence and global services are part of the observed pattern; do not assume a separate repository abstraction isolates storage from all business logic.

Headless/isolate startup initializes its own Rust bridge and required services. `lib/services/rustpush/rustpush_service.dart` contains isolate and CloudKit-sync orchestration; `StartupTasks.initIsolateServices()` defines the reduced filesystem/settings/database/method-channel/lifecycle setup. Changes to initialization or persistence must consider both foreground and background execution.

### Platform boundaries

The repository contains Android, iOS, Linux, macOS, Windows and web directories. `rust_builder/pubspec.yaml` advertises FFI plugins for the **five native platforms**, not web. Native platform code and plugins provide notifications, lifecycle, telephony and window behavior. Android retains the `com.bluebubbles.messaging` namespace and flavor-specific identities.

Conditional web model exports and the ObjectBox bypass show a distinct web path; they do **not** prove the current application builds or functions in a browser. Native FFI initialization and `dart:io` usage require target-specific investigation. README positioning emphasizes Android/Windows and requires access to a Mac and Apple ID; platform directory presence is not a support guarantee.

## Conventions (Observed)

### Error handling

- `lib/main.dart` installs Flutter and zoned error handlers and renders startup failure UI on initialization errors.
- Adapter operations mix typed domain returns, booleans, nullable results and generic exceptions; there is no single observed universal error envelope (`BackendService`, `HttpBackend`).
- Optional work sometimes catches/suppresses failures, while send failures reconcile local state and notify through `ActionHandler`.
- Rust uses `anyhow` and bridge exception conversion, but handwritten code also contains `unwrap()` / `expect()` assumptions. These warrant boundary-specific validation rather than a blanket claim that all native failures return structured errors (`rust/src/api/api.rs`).

### API shapes and type safety

- The application boundary is a typed Dart interface plus generated Dart–Rust bindings, alongside a retained HTTP/Socket.IO protocol—not GraphQL.
- HTTP methods commonly unwrap `response.data['data']` then call `Chat.fromMap` / `Message.fromMap`. Multipart attributed-message fields include `text`, `mention`, `partIndex`; transport mode strings include `private-api` and `apple-script` (`http_service.dart`).
- Socket event names are kebab-case (`new-message`, `started-typing`); payloads use runtime JSON maps. Some acknowledgements are decrypted before JSON decoding (`socket_service.dart`).
- Dart uses null-safe types, but `dynamic`, `Map<String, dynamic>`, casts and null assertions remain important runtime boundaries. Generated code must not be counted as evidence of handwritten strictness.
- `ParticipantOp.Add` / `Remove` become lowercase wire strings in the HTTP adapter; casing is boundary-specific.
- A handwritten `unsafe` block exists in Rust's pointer-based callback integration. FFI lifetime/pointer assumptions require focused review before modification (`rust/src/api/api.rs`).

### Observability and transport policy

`lib/utils/logger/logger.dart` centralizes console logging and non-web file output, with 1 MB rotation and five rotated files. The default log threshold is info (`lib/database/global/settings.dart` also defaults to `Level.info`); user settings can change it. PrettyPrinter omits boxes for debug/info/warning and retains them for error/trace/fatal. Box decoration is separate from level filtering: info and warning are emitted by default, trace is not. This is application logging, not evidence of a structured JSON telemetry or health-check system.

`main.dart` installs `BadCertOverride` globally. Its callback in `lib/services/network/http_overrides.dart` selectively accepts otherwise-invalid certificates based on the configured server address (suffix/regex matching). It is **not** an unconditional accept-all callback; matching policy and global scope are sensitive review points for any transport changes. No security audit was performed.

### Testing and CI

Tracked test-path inventory found `test_driver/integration_test.dart`, a driver wrapper rather than scenario coverage. No app test scenarios were identified in the inspected inventory; that is not a claim about external or unavailable submodule tests, nor a measured coverage percentage.

The sole visible workflow, `.github/workflows/build.yml`, checks out submodules and builds an alpha/debug ARM64 APK. It does not run explicit Flutter tests, analyzer or Rust tests. A comment says the first build is expected to fail pending an FFmpeg dependency fix. This is a documented concern, **not a verified current CI failure**. Artifact upload follows the build with normal success gating; it is not configured to continue after a failed build.

`analysis_options.yaml` configures lints and exceptions. `CONTRIBUTING.md` asks for clean/commented code and Dart documentation conventions, but contains historical BlueBubbles URLs and Flutter 1.22.4 custom-engine advice. Treat current manifests and workflow as stronger toolchain evidence, not that old engine guide.

## Signals / Active Considerations

1. **Default-versus-legacy ambiguity:** RustPush is selected, while HTTP/server setup code remains. Trace the concrete caller before altering transports, capability handling or setup behavior.
2. **Concentrated responsibilities:** `rustpush_service.dart` is 5,042 lines; handwritten `rust/src/api/api.rs` 2,802; `http_service.dart` 1,701; `action_handler.dart` 695 at this snapshot. These are navigation/blast-radius signals, not refactor requests.
3. **Missing native dependencies:** initialize/audit required submodules before claiming a complete native build map. Native toolchains, certificate inputs and platform plugins complicate validation.
4. **Generated contracts:** keep Dart/Rust FRB versions and generated outputs aligned. Follow generation configuration instead of editing generated bindings as primary source.
5. **Validation gap:** the visible CI is an APK build gate, not a cross-platform behavior/test matrix. Define focused tests before behavior changes; browser-observable changes need browser regression coverage if that target is actually supported.
6. **UI/I/O coupling:** service code includes UI interactions and network/storage operations. Test seams and background-isolate behavior need explicit consideration when planning changes.
7. **Sensitive inputs:** account, keychain, push and server-auth boundaries exist. `.env` is declared as an asset and optionally loaded; its contents and credential files were deliberately not inspected or copied. This map makes no claim about their safety or contents.

## Verification and Limits

Evidence consists of direct source/manifest reads, two parallel read-only reconnaissance reports, tracked test/workflow inventory, submodule status and file-size checks. No application code or configuration was changed. No dependency installation, build, tests, app launch or network/auth flow was attempted for this documentation-only task.

Browser/Playwright verification is not applicable to this map itself: it changes no runtime or browser-observable behavior. Current platform operability, live API schemas, CI outcomes and submodule internals remain unverified. This document records existing terms; it does not introduce a new domain contract or glossary.

Start with `StartupTasks`, then `BackendService`, `RustPushBackend` and `ActionHandler`. Once this map exists, use `survey-context` to consume it rather than deriving it again for every task.
