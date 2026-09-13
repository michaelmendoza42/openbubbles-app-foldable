import 'package:bluebubbles/app/wrappers/tablet_mode_wrapper.dart';
import 'package:bluebubbles/database/global/settings.dart';
import 'package:bluebubbles/services/backend/settings/settings_service.dart';
import 'package:bluebubbles/services/ui/navigator/navigator_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    ss.prefs = await SharedPreferences.getInstance();
  });
  setUp(() { ss.settings = Settings(); });

  testWidgets('Back honors selection on the initial nested list route', (tester) async {
    var dismissed = 0;
    await tester.pumpWidget(GetMaterialApp(home: Navigator(
      key: Get.nestedKey(1),
      onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) { if (!didPop) dismissed++; },
        child: const SizedBox(key: Key('selected-list')),
      )),
    )));
    await tester.pumpAndSettle();
    expect(await ns.backConversationView(tester.element(find.byKey(const Key('selected-list'))), allowRootFallback: false), isTrue);
    expect(dismissed, 1);
    expect(Get.keys[1]!.currentState!.canPop(), isFalse);
    expect(Get.key.currentState!.canPop(), isFalse);
  });

  testWidgets('Back dismisses chat transient state before popping its route', (tester) async {
    var selected = true;
    await tester.pumpWidget(GetMaterialApp(home: Navigator(
      key: Get.nestedKey(2),
      onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => const SizedBox()),
    )));
    await tester.pumpAndSettle();
    Get.keys[2]!.currentState!.push(MaterialPageRoute(builder: (_) => StatefulBuilder(
      builder: (context, update) => PopScope(
        canPop: !selected,
        onPopInvokedWithResult: (didPop, result) { if (!didPop) update(() => selected = false); },
        child: const SizedBox(key: Key('selected-chat')),
      ),
    )));
    await tester.pumpAndSettle();
    expect(await ns.backConversationView(tester.element(find.byKey(const Key('selected-chat'))), allowRootFallback: false), isTrue);
    await tester.pumpAndSettle();
    expect(selected, isFalse);
    expect(Get.keys[2]!.currentState!.canPop(), isTrue);
    expect(await ns.backConversationView(tester.element(find.byKey(const Key('selected-chat'))), allowRootFallback: false), isTrue);
    await tester.pumpAndSettle();
    expect(Get.keys[2]!.currentState!.canPop(), isFalse);
  });

  testWidgets('Back pops visible root settings before an underlying search pane', (tester) async {
    await tester.pumpWidget(GetMaterialApp(home: Navigator(
      key: Get.nestedKey(1),
      onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => const SizedBox()),
    )));
    await tester.pumpAndSettle();
    Get.keys[1]!.currentState!.push(MaterialPageRoute(builder: (_) => const Text('Search')));
    await tester.pumpAndSettle();
    Get.key.currentState!.push(MaterialPageRoute(builder: (_) => const SizedBox(key: Key('settings-root'))));
    await tester.pumpAndSettle();
    expect(await ns.backConversationView(tester.element(find.byKey(const Key('settings-root')))), isTrue);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-root')), findsNothing);
    expect(Get.keys[1]!.currentState!.canPop(), isTrue);
    expect(find.text('Search'), findsOneWidget);
  });

  testWidgets('portrait-hidden left pane relinquishes keyboard focus', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: TabletModeWrapper(
      minRatio: 0.33, maxRatio: 0.5,
      titleBarBuilder: (child) => Material(child: child),
      splitLayoutBuilder: (context) => MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height,
      showRightInSinglePane: () => true,
      left: TextField(focusNode: focus),
      right: const Text('Visible chat'),
    )));
    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    tester.view.physicalSize = const Size(800, 1280);
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isFalse);
    expect(focus.canRequestFocus, isFalse);
    expect(find.text('Visible chat'), findsOneWidget);
  });
}
