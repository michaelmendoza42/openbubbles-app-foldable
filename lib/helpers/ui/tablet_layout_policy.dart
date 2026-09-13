/// Whether the conversation/settings split pane should be shown for this view.
///
/// Mobile views use the split pane only in landscape. Desktop and web retain
/// the existing width/aspect behavior.
bool usesTabletSplitLayout({
  required bool tabletMode,
  required bool isPhone,
  required double width,
  required double height,
  required bool isBubble,
  required bool isDesktop,
  required bool isWeb,
}) {
  if (!tabletMode || isBubble || width <= 600) return false;

  if (isDesktop || isWeb) {
    return !isPhone || width / height > 0.8;
  }

  return width > height;
}
