import 'package:bluebubbles/helpers/ui/tablet_layout_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  bool split({
    required double width,
    required double height,
    bool tabletMode = true,
    bool isPhone = false,
    bool isBubble = false,
    bool isDesktop = false,
    bool isWeb = false,
  }) =>
      usesTabletSplitLayout(
        tabletMode: tabletMode,
        isPhone: isPhone,
        width: width,
        height: height,
        isBubble: isBubble,
        isDesktop: isDesktop,
        isWeb: isWeb,
      );

  group('tablet split layout policy', () {
    test('uses one pane for qualifying mobile portrait tablets', () {
      expect(split(width: 800, height: 1280), isFalse);
      expect(split(width: 1024, height: 1366), isFalse);
    });

    test('retains the existing split layout for qualifying mobile landscape',
        () {
      expect(split(width: 1280, height: 800), isTrue);
      expect(split(width: 1366, height: 1024), isTrue);
    });

    test('keeps the mobile threshold and tablet-mode opt out', () {
      expect(split(width: 600, height: 500), isFalse);
      expect(split(width: 601, height: 500), isTrue);
      expect(split(width: 800, height: 800), isFalse);
      expect(split(width: 1280, height: 800, tabletMode: false), isFalse);
    });

    test('does not enable split layout for bubbles', () {
      expect(split(width: 1280, height: 800, isBubble: true), isFalse);
    });

    test('preserves desktop and web aspect-ratio behavior', () {
      expect(split(width: 800, height: 1280, isPhone: false, isDesktop: true),
          isTrue);
      expect(split(width: 800, height: 1280, isPhone: true, isDesktop: true),
          isFalse);
      expect(
          split(width: 800, height: 900, isPhone: true, isWeb: true), isTrue);
    });
  });
}
