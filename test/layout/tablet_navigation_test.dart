import 'package:bluebubbles/app/wrappers/tablet_mode_wrapper.dart';
import 'package:bluebubbles/database/global/settings.dart';
import 'package:bluebubbles/helpers/ui/tablet_layout_policy.dart';
import 'package:bluebubbles/services/backend/settings/settings_service.dart';
import 'package:bluebubbles/services/ui/navigator/navigator_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    ss.prefs = await SharedPreferences.getInstance();
  });

  setUp(() {
    ss.settings = Settings();
    ss.settings.tabletMode.value = true;
  });

  testWidgets(
      'a nested right route opened in portrait stays visible through rotations and shared Back',
      (tester) async {
    final counters = _RouteCounters();
    _setViewSize(tester, const Size(800, 1280));
    addTearDown(() => _resetViewSize(tester));
    await tester.pumpWidget(_conversationHarness(counters));

    expect(Get.keys[1]?.currentState, isNotNull);
    expect(ns.width(tester.element(find.byKey(const Key('conversation-list')))),
        800);

    await tester.tap(find.byKey(const Key('open-conversation')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chat-pane')), findsOneWidget);
    expect(_isOffstage(tester, const Key('conversation-list')), isTrue);
    expect(
        ns.width(tester.element(
            find.byKey(const Key('conversation-list'), skipOffstage: false))),
        800);
    expect(tester.getSize(find.byKey(const Key('chat-pane'))).width, 800);
    expect(ns.width(tester.element(find.byKey(const Key('chat-pane')))), 800);
    expect(counters.created, 1);
    expect(counters.disposed, 0);
    expect(Get.key.currentState!.canPop(), isFalse);

    await tester.enterText(
        find.byKey(const Key('draft')), 'portrait-origin draft');
    for (final size in [
      const Size(1280, 800),
      const Size(800, 1280),
      const Size(1280, 800),
      const Size(800, 1280)
    ]) {
      _setViewSize(tester, size);
      await tester.pumpAndSettle();
      expect(find.text('portrait-origin draft'), findsOneWidget);
      final paneWidth =
          tester.getSize(find.byKey(const Key('chat-pane'))).width;
      expect(ns.width(tester.element(find.byKey(const Key('chat-pane')))),
          paneWidth);
      expect(counters.created, 1);
      expect(counters.disposed, 0);
    }

    expect(_isOffstage(tester, const Key('conversation-list')), isTrue);
    expect(tester.getSize(find.byKey(const Key('chat-pane'))).width, 800);
    expect(
        await ns.backConversationView(
            tester.element(find.byKey(const Key('chat-pane')))),
        isTrue);
    await tester.pumpAndSettle();

    expect(_isOffstage(tester, const Key('conversation-list')), isFalse);
    expect(_isOffstage(tester, const Key('chat-pane')), isTrue);
    expect(counters.disposed, 1);
    expect(Get.key.currentState!.canPop(), isFalse);
  });

  testWidgets(
      'settings detail opened in portrait remains the active pane across rotation and Back',
      (tester) async {
    _setViewSize(tester, const Size(800, 1280));
    addTearDown(() => _resetViewSize(tester));
    await tester.pumpWidget(_settingsHarness());

    await tester.tap(find.byKey(const Key('open-settings-detail')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-detail')), findsOneWidget);
    expect(_isOffstage(tester, const Key('settings-list')), isTrue);
    expect(tester.getSize(find.byKey(const Key('settings-detail'))).width, 800);
    expect(ns.width(tester.element(find.byKey(const Key('settings-detail')))),
        800);
    expect(Get.key.currentState!.canPop(), isFalse);

    _setViewSize(tester, const Size(1280, 800));
    await tester.pumpAndSettle();
    expect(_isOffstage(tester, const Key('settings-list')), isFalse);
    expect(_isOffstage(tester, const Key('settings-detail')), isFalse);
    final detailWidth =
        tester.getSize(find.byKey(const Key('settings-detail'))).width;
    expect(detailWidth, greaterThan(600));
    expect(ns.width(tester.element(find.byKey(const Key('settings-detail')))),
        detailWidth);

    _setViewSize(tester, const Size(800, 1280));
    await tester.pumpAndSettle();
    expect(_isOffstage(tester, const Key('settings-list')), isTrue);
    expect(tester.getSize(find.byKey(const Key('settings-detail'))).width, 800);

    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(_isOffstage(tester, const Key('settings-list')), isFalse);
    expect(find.byKey(const Key('settings-detail'), skipOffstage: false),
        findsNothing);
    expect(Get.key.currentState!.canPop(), isFalse);
  });
}

Widget _conversationHarness(_RouteCounters counters) => GetMaterialApp(
      navigatorKey: ns.key,
      home: _BackScope(
        child: TabletModeWrapper(
          initialRatio: 0.4,
          minRatio: 0.33,
          maxRatio: 0.5,
          titleBarBuilder: (child) => Material(child: child),
          splitLayoutBuilder: _mobileSplitLayout,
          showRightInSinglePane: () =>
              Get.keys[2]?.currentState?.canPop() ?? false,
          left: LayoutBuilder(
            builder: (context, constraints) {
              ns.maxWidthLeft = constraints.maxWidth;
              return Navigator(
                key: Get.nestedKey(1),
                observers: [TabletPaneNavigatorObserver()],
                onGenerateRoute: (_) => MaterialPageRoute(
                  builder: (context) => _ListPane(
                    key: const Key('conversation-list'),
                    buttonKey: const Key('open-conversation'),
                    onOpen: () => ns.pushAndRemoveUntil(
                      context,
                      _DraftPane(counters: counters),
                      (route) => route.isFirst,
                    ),
                  ),
                ),
              );
            },
          ),
          right: LayoutBuilder(
            builder: (context, constraints) {
              ns.maxWidthRight = constraints.maxWidth;
              return Navigator(
                key: Get.nestedKey(2),
                observers: [TabletPaneNavigatorObserver()],
                onGenerateRoute: (_) => MaterialPageRoute(
                  builder: (_) => const SizedBox(key: Key('chat-pane')),
                ),
              );
            },
          ),
        ),
      ),
    );

Widget _settingsHarness() => GetMaterialApp(
      navigatorKey: ns.key,
      home: _BackScope(
        child: TabletModeWrapper(
          initialRatio: 0.4,
          minRatio: 0.33,
          maxRatio: 0.5,
          titleBarBuilder: (child) => Material(child: child),
          splitLayoutBuilder: _mobileSplitLayout,
          showRightInSinglePane: () =>
              Get.keys[3]?.currentState?.canPop() ?? false,
          left: LayoutBuilder(
            builder: (context, constraints) {
              ns.maxWidthLeft = constraints.maxWidth;
              return Navigator(
                key: Get.nestedKey(1),
                observers: [TabletPaneNavigatorObserver()],
                onGenerateRoute: (_) => MaterialPageRoute(
                  builder: (context) => _ListPane(
                    key: const Key('settings-list'),
                    buttonKey: const Key('open-settings-detail'),
                    onOpen: () =>
                        ns.pushSettings(context, const _SettingsDetail()),
                  ),
                ),
              );
            },
          ),
          right: LayoutBuilder(
            builder: (context, constraints) {
              ns.maxWidthSettings = constraints.maxWidth;
              return Navigator(
                key: Get.nestedKey(3),
                observers: [TabletPaneNavigatorObserver()],
                onGenerateRoute: (_) => MaterialPageRoute(
                  builder: (_) => const SizedBox(key: Key('settings-initial')),
                ),
              );
            },
          ),
        ),
      ),
    );

class _BackScope extends StatelessWidget {
  const _BackScope({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: <T>(bool didPop, T? result) async {
          if (!didPop && !await ns.backConversationView(context, allowRootFallback: false)) {
            SystemNavigator.pop();
          }
        },
        child: child,
      );
}

void _setViewSize(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
}

void _resetViewSize(WidgetTester tester) {
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
}

bool _mobileSplitLayout(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return usesTabletSplitLayout(
    tabletMode: true,
    isPhone: false,
    width: size.width,
    height: size.height,
    isBubble: false,
    isDesktop: false,
    isWeb: false,
  );
}

bool _isOffstage(WidgetTester tester, Key key) {
  var hidden = false;
  find
      .byKey(key, skipOffstage: false)
      .evaluate()
      .single
      .visitAncestorElements((element) {
    if (element.widget case Offstage widget) hidden = hidden || widget.offstage;
    return true;
  });
  return hidden;
}

class _ListPane extends StatelessWidget {
  const _ListPane({super.key, required this.buttonKey, required this.onOpen});

  final Key buttonKey;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => SizedBox.expand(
        child: Center(
            child: ElevatedButton(
                key: buttonKey, onPressed: onOpen, child: const Text('Open'))),
      );
}

class _DraftPane extends StatefulWidget {
  const _DraftPane({required this.counters});

  final _RouteCounters counters;

  @override
  State<_DraftPane> createState() => _DraftPaneState();
}

class _DraftPaneState extends State<_DraftPane> {
  final controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.counters.created++;
  }

  @override
  void dispose() {
    widget.counters.disposed++;
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.expand(
        key: const Key('chat-pane'),
        child: Column(
          children: [
            Text('width:${ns.width(context).round()}'),
            TextField(key: const Key('draft'), controller: controller),
          ],
        ),
      );
}

class _SettingsDetail extends StatelessWidget {
  const _SettingsDetail();

  @override
  Widget build(BuildContext context) => SizedBox.expand(
        key: const Key('settings-detail'),
        child: Column(
          children: [
            Text('width:${ns.width(context).round()}'),
          ],
        ),
      );
}

class _RouteCounters {
  int created = 0;
  int disposed = 0;
}
