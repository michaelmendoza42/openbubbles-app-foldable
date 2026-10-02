import 'dart:convert';
import 'dart:io';

import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/text_field/conversation_text_field.dart';
import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/types/constants.dart';
import 'package:bluebubbles/services/backend/settings/settings_service.dart';
import 'package:bluebubbles/services/ui/chat/conversation_view_controller.dart';
import 'package:bluebubbles/services/ui/theme/themes_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tuple/tuple.dart';

/// Account-free Android fixture for the production conversation draft surface.
///
/// The fixture creates a dedicated ObjectBox store and a temporary attachment,
/// then mounts the production controller and [ConversationTextField], including
/// its reply and attachment holders. No transport or account-backed message
/// load is initialized. `test_driver/verify_android_production_draft.py`
/// listens for rotation checkpoints and drives physical WindowManager
/// orientation serially.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'production conversation draft, reply and attachment survive repeated Android rotations before Back',
      (tester) async {
    ss.prefs = await SharedPreferences.getInstance();
    await ss.prefs.clear();
    ss.settings = Settings();
    ss.settings.skin.value = Skins.Material;
    ss.settings.finishedSetup.value = false;
    final fixture = await _ProductionDraftFixture.create();
    addTearDown(fixture.dispose);
    final controller = cvc(fixture.chat);
    // Seed the production reply state before the holder's first layout so its
    // AnimatedSize begins at the complete draft height.
    final reply = Message.findOne(guid: fixture.replyGuid);
    expect(reply, isNotNull);
    controller.replyToMessage = Tuple2(reply!, 0);
    await tester.pumpWidget(
        _ConversationRouteHarness(fixture: fixture, controller: controller));
    await tester.tap(find.byKey(const Key('open-production-conversation')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 250));

    expect(controller.textController.text, fixture.persistedDraft);
    expect(controller.pickedAttachments.single.path, fixture.attachment.path);
    expect(find.text(fixture.attachmentName), findsOneWidget);

    // The reply target was resolved from the isolated ObjectBox store before
    // mounting, using the same Message.findOne path as the controller.
    expect(find.textContaining(fixture.replyText), findsOneWidget);

    // Mutate the production text controller without opening a platform IME;
    // the physical rotation fixture must not confound draft preservation with
    // keyboard resize behavior.
    controller.textController.text = fixture.editedDraft;
    await tester.pumpAndSettle();
    expect(controller.textController.text, fixture.editedDraft);

    for (final portrait in <bool>[true, false, true, false, true]) {
      await _awaitPhysicalRotation(tester, portrait: portrait);
      expect(cvc(fixture.chat), same(controller),
          reason:
              'a MediaQuery orientation change must not recreate the controller');
      expect(controller.textController.text, fixture.editedDraft);
      expect(controller.replyToMessage?.item1.guid, fixture.replyGuid);
      expect(controller.pickedAttachments.single.path, fixture.attachment.path);
      expect(find.text(fixture.attachmentName), findsOneWidget);
      expect(find.textContaining(fixture.replyText), findsOneWidget);
    }

    // The route and all transient state remain mounted until Back is actually
    // dispatched. This catches a premature pop/close during the transitions.
    expect(find.byKey(const Key('production-draft-pane')), findsOneWidget);
    expect(controller.replyToMessage?.item1.guid, fixture.replyGuid);
    print('E01_DRAFT_READY_FOR_BACK');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
        find.byKey(const Key('production-conversation-root')), findsOneWidget);
    expect(find.byKey(const Key('production-draft-pane')), findsNothing);
    print('E01_PRODUCTION_DRAFT_PASSED');
  });
}

Future<void> _awaitPhysicalRotation(WidgetTester tester,
    {required bool portrait}) async {
  print('E01_DRAFT_ROTATE_REQUEST portrait=$portrait');
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    if (size.width != size.height && (size.height > size.width) == portrait) {
      print(
          'E01_DRAFT_ROTATED portrait=$portrait width=${size.width.round()} height=${size.height.round()}');
      return;
    }
  }
  fail(
      'Host did not rotate the production fixture to ${portrait ? 'portrait' : 'landscape'}');
}

class _ConversationRouteHarness extends StatelessWidget {
  const _ConversationRouteHarness({
    required this.fixture,
    required this.controller,
  });

  final _ProductionDraftFixture fixture;
  final ConversationViewController controller;

  @override
  Widget build(BuildContext context) => AdaptiveTheme(
        light: ts.whiteLightTheme,
        dark: ts.oledDarkTheme,
        initial: AdaptiveThemeMode.light,
        builder: (theme, darkTheme) => GetMaterialApp(
          theme: theme,
          darkTheme: darkTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: SizedBox(
                  key: const Key('production-conversation-root'),
                  child: ElevatedButton(
                    key: const Key('open-production-conversation'),
                    onPressed: () =>
                        Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => _ProductionConversationDraftPane(
                        controller: controller,
                      ),
                    )),
                    child: const Text('Open production conversation'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _ProductionConversationDraftPane extends StatelessWidget {
  const _ProductionConversationDraftPane({required this.controller});

  final ConversationViewController controller;

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          controller.close();
          Navigator.of(context).pop();
        },
        child: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              key: const Key('production-draft-pane'),
              // The landscape viewport may be shorter than the complete
              // production reply/attachment/text composer. Scrolling is a
              // fixture-only container; the child is the unchanged composer.
              height: 350,
              child: SingleChildScrollView(
                reverse: true,
                child: ConversationTextField(parentController: controller),
              ),
            ),
          ),
        ),
      );
}

class _ProductionDraftFixture {
  _ProductionDraftFixture({
    required this.root,
    required this.store,
    required this.chat,
    required this.attachment,
    required this.persistedDraft,
    required this.editedDraft,
    required this.replyGuid,
    required this.replyText,
    required this.attachmentName,
  });

  final Directory root;
  final Store store;
  final Chat chat;
  final File attachment;
  final String persistedDraft;
  final String editedDraft;
  final String replyGuid;
  final String replyText;
  final String attachmentName;

  static Future<_ProductionDraftFixture> create() async {
    final root =
        await Directory.systemTemp.createTemp('openbubbles-draft-fixture-');
    final store =
        await openStore(directory: Directory('${root.path}/objectbox').path);
    _bindIsolatedStore(store);

    const attachmentName = 'rotation-draft-attachment.txt';
    final attachment = File('${root.path}/$attachmentName');
    await attachment.writeAsString('isolated attachment fixture');
    const persistedDraft = 'Persisted portrait draft';
    const editedDraft = 'Edited draft survives rotation';
    const replyGuid = 'fixture-reply-message';
    const replyText = 'Persisted reply target';
    final handle = Handle(
      address: '+15555550123',
      originalROWID: 1,
      service: 'iMessage',
    ).save();
    // A local SMS-shaped GUID keeps the fixture account-free while exercising
    // the same production controller and draft widgets.
    final chat = Chat(
      guid: 'SMS;fixture-production-chat',
      displayName: 'Fixture conversation',
      usingHandle: 'tel:+15555550124',
      participants: <Handle>[handle],
      textFieldText: persistedDraft,
      textFieldAnnotations: jsonEncode(<String, Object>{
        'annotations': <Object>[
          <String, Object>{
            'range': <int>[0, persistedDraft.length]
          }
        ],
        'cache': <String, String>{},
      }),
      textFieldAttachments: <String>[attachment.path],
    ).save();
    Message(
      guid: replyGuid,
      text: replyText,
      dateCreated: DateTime.utc(2024, 1, 1),
      isFromMe: false,
      handle: handle,
    ).save(chat: chat);
    return _ProductionDraftFixture(
      root: root,
      store: store,
      chat: chat,
      attachment: attachment,
      persistedDraft: persistedDraft,
      editedDraft: editedDraft,
      replyGuid: replyGuid,
      replyText: replyText,
      attachmentName: attachmentName,
    );
  }

  static void _bindIsolatedStore(Store store) {
    Database.store = store;
    Database.attachments = store.box<Attachment>();
    Database.chats = store.box<Chat>();
    Database.contacts = store.box<Contact>();
    Database.fcmData = store.box<FCMData>();
    Database.handles = store.box<Handle>();
    Database.messages = store.box<Message>();
    Database.themes = store.box<ThemeStruct>();
    Database.themeEntries = store.box<ThemeEntry>();
    // ignore: deprecated_member_use_from_same_package
    Database.themeObjects = store.box<ThemeObject>();
  }

  Future<void> dispose() async {
    if (Get.isRegistered<ConversationViewController>(tag: chat.guid)) {
      Get.delete<ConversationViewController>(tag: chat.guid, force: true);
    }
    store.close();
    if (root.existsSync()) await root.delete(recursive: true);
  }
}
