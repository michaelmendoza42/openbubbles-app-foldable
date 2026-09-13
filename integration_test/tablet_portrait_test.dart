import 'package:bluebubbles/app/wrappers/tablet_mode_wrapper.dart';
import 'package:bluebubbles/database/global/settings.dart';
import 'package:bluebubbles/helpers/ui/tablet_layout_policy.dart';
import 'package:bluebubbles/services/backend/settings/settings_service.dart';
import 'package:bluebubbles/services/ui/navigator/navigator_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Isolated native fixture: real wrapper, navigator service and preferences,
// but no Apple account, network transport, real conversation or message send.
// test_driver/tablet_rotation_probe.py drives OS rotation at the log checkpoints.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native tablet rotation keeps a portrait-origin pane and draft', (tester) async {
    ss.prefs = await SharedPreferences.getInstance();
    ss.settings = Settings();
    ss.settings.tabletMode.value = true;
    await tester.pumpWidget(GetMaterialApp(home: TabletModeWrapper(
      initialRatio: 0.4,
      minRatio: 0.33,
      maxRatio: 0.5,
      titleBarBuilder: (child) => Material(child: child),
      splitLayoutBuilder: (context) {
        final size = MediaQuery.sizeOf(context);
        return usesTabletSplitLayout(tabletMode: true, isPhone: false,
            width: size.width, height: size.height, isBubble: false,
            isDesktop: false, isWeb: false);
      },
      showRightInSinglePane: () => Get.keys[2]?.currentState?.canPop() ?? false,
      left: Navigator(key: Get.nestedKey(1), onGenerateRoute: (_) => MaterialPageRoute(
        builder: (context) => Center(child: ElevatedButton(
          key: const Key('open-fixture'),
          onPressed: () => ns.pushAndRemoveUntil(context, const _DraftFixture(), (route) => route.isFirst),
          child: const Text('Open test conversation'),
        )),
      )),
      right: LayoutBuilder(builder: (context, constraints) {
        ns.maxWidthRight = constraints.maxWidth;
        return Navigator(key: Get.nestedKey(2), observers: [TabletPaneNavigatorObserver()],
          onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => const SizedBox()));
      }),
    )));
    await _rotate(tester, portrait: true);
    await tester.tap(find.byKey(const Key('open-fixture')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('fixture-draft')), 'Portrait draft survives');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    for (final portrait in [false, true, false, true]) {
      await _rotate(tester, portrait: portrait);
      expect(find.text('Portrait draft survives'), findsOneWidget);
      final context = tester.element(find.byKey(const Key('fixture-pane')));
      final width = tester.getSize(find.byKey(const Key('fixture-pane'))).width;
      expect(ns.width(context), closeTo(width, 1));
      if (portrait) expect(width, closeTo(MediaQuery.sizeOf(context).width, 1));
      expect(Get.key.currentState!.canPop(), isFalse);
    }
    print('E01_CAPTURE_PORTRAIT');
    await tester.pump(const Duration(seconds: 2));
    ss.settings.lockToPortrait.value = true;
    await ss.settings.saveOne('lockToPortrait');
    await ss.prefs.reload();
    expect(Settings.getSettings().lockToPortrait.value, isTrue);
    // Do not treat preference storage as evidence of OS lock enforcement.
    ss.settings.lockToPortrait.value = false;
    await ss.settings.saveOne('lockToPortrait');
    await tester.tap(find.byKey(const Key('fixture-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('open-fixture')), findsOneWidget);
    print('E01_NATIVE_LAYOUT_PASSED');
    await tester.pump(const Duration(seconds: 3));
  });
}

Future<void> _rotate(WidgetTester tester, {required bool portrait}) async {
  print(portrait ? 'E01_ROTATE_PORTRAIT' : 'E01_ROTATE_LANDSCAPE');
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    if ((size.height > size.width) == portrait && size.height != size.width) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('Host did not rotate the native display to ${portrait ? "portrait" : "landscape"}');
}

class _DraftFixture extends StatefulWidget {
  const _DraftFixture();
  @override
  State<_DraftFixture> createState() => _DraftFixtureState();
}

class _DraftFixtureState extends State<_DraftFixture> {
  final controller = TextEditingController();
  @override
  void dispose() { controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => SizedBox.expand(
    key: const Key('fixture-pane'),
    child: Column(children: [
      ElevatedButton(key: const Key('fixture-back'),
          onPressed: () => ns.backConversationView(context), child: const Text('Back')),
      const Text('OpenBubbles portrait regression fixture'),
      TextField(key: const Key('fixture-draft'), controller: controller),
    ]),
  );
}
