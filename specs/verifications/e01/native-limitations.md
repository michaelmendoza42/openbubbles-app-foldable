# e01 native orientation limitations

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

## Native enforcement is not proven

This is not a claim that every OS will enforce the request. The required e01
native device matrix has not been completed. Alpha/debug APK builds now pass
using the repository CI's ignored placeholder FairPlay inputs. An isolated native
fixture passed on the Android 16 tablet, exercising real OS rotation of the
production pane wrapper/navigation service and preference save/reload. This
fixture does not exercise the complete account-backed conversation screen,
process restart or OS enforcement of the app's portrait-lock request. In particular:

- Android 16 can ignore app orientation requests on displays with a smallest
  width of at least 600dp while targeting API 36.
- iPad only honors Flutter preferred orientations when iPad multitasking is
  disabled.

No Android compatibility opt-out, target-SDK downgrade, iPad
`UIRequiresFullScreen` change, or multitasking restriction was made. Those are
product/platform trade-offs outside this implementation and remain native
acceptance blockers until the contract matrix records actual device results.
