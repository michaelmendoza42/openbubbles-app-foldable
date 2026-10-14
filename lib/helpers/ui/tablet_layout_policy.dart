/// Whether the conversation/settings split pane should be shown for this view.
///
/// Mobile views use the split pane only in landscape, and never while Lock to
/// Portrait is on (the screen may still rotate; the layout stays single-pane).
/// Desktop and web retain the existing width/aspect behavior.
bool usesTabletSplitLayout({
  required bool tabletMode,
  required bool isPhone,
  required double width,
  required double height,
  required bool isBubble,
  required bool isDesktop,
  required bool isWeb,
  bool lockToPortrait = false,
}) {
  if (!tabletMode || isBubble || width <= 600) return false;

  if (isDesktop || isWeb) {
    return !isPhone || width / height > 0.8;
  }

  return !lockToPortrait && width > height;
}
