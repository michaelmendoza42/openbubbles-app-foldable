import 'package:bluebubbles/database/global/settings.dart';
import 'package:bluebubbles/services/backend/settings/settings_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    ss.prefs = await SharedPreferences.getInstance();
  });

  setUp(() async {
    await ss.prefs.clear();
    ss.settings = Settings();
  });

  test('missing portrait-lock key defaults to false in both deserializers', () async {
    final loaded = Settings.fromMap({'allowUpsideDownRotation': true});
    expect(loaded.lockToPortrait.value, isFalse);

    await Settings.updateFromMap({'allowUpsideDownRotation': true});
    expect(ss.settings.lockToPortrait.value, isFalse);
  });

  test('portrait lock round trips through an awaited single-setting save', () async {
    ss.settings.lockToPortrait.value = true;
    await ss.settings.saveOne('lockToPortrait');

    expect(ss.prefs.getBool('lockToPortrait'), isTrue);
    expect(Settings.getSettings().lockToPortrait.value, isTrue);
  });

  test('restore saves the portrait lock durably before completing and applies the common policy', () async {
    final calls = <MethodCall>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await ss.restoreSettings({
      'lockToPortrait': true,
      'allowUpsideDownRotation': true,
    }, headless: true);

    expect(ss.settings.lockToPortrait.value, isTrue);
    expect(ss.settings.allowUpsideDownRotation.value, isTrue);
    expect(ss.prefs.getBool('lockToPortrait'), isTrue);
    expect(Settings.getSettings().lockToPortrait.value, isTrue);
    expect(calls, isEmpty);
  });

  test('portrait lock overrides upside-down while unlock restores user rotation choices', () {
    expect(
      SettingsService.orientationPolicy(lockToPortrait: true, allowUpsideDownRotation: true),
      const [DeviceOrientation.portraitUp],
    );
    expect(
      SettingsService.orientationPolicy(lockToPortrait: false, allowUpsideDownRotation: false),
      const [
        DeviceOrientation.landscapeRight,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.portraitUp,
      ],
    );
    expect(
      SettingsService.orientationPolicy(lockToPortrait: false, allowUpsideDownRotation: true),
      const [
        DeviceOrientation.landscapeRight,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ],
    );
  });

  test('headless policy application never calls the platform channel', () async {
    final calls = <MethodCall>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    ss.settings.lockToPortrait.value = true;
    await ss.applyOrientationPolicy(headless: true);

    expect(calls, isEmpty);
  });
}
