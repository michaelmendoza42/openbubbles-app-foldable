import 'dart:io';

import 'package:bluebubbles/app/layouts/settings/widgets/content/settings_switch.dart';
import 'package:bluebubbles/database/global/settings.dart';
import 'package:bluebubbles/services/backend/settings/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Android-only native fixture. It uses SettingsService and the same
// SettingsSwitch control used by MiscPanel, but not MiscPanel itself: the full
// panel needs initialized production navigation/theme state and produces an
// invalid transform in an isolated native test. It does not initialize an
// account or transport. test_driver/verify_android_orientation.py supplies
// NATIVE_PHASE and drives actual WindowManager rotation/force-stop/relaunch.
const _phase = String.fromEnvironment('NATIVE_PHASE', defaultValue: 'lock');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('portrait-lock fixture persists across a native relaunch',
      (tester) async {
    ss.prefs = await SharedPreferences.getInstance();
    ss.settings = Settings.getSettings();

    if (_phase == 'lock') {
      ss.settings.lockToPortrait.value = false;
      await ss.settings.saveOne('lockToPortrait');
      await ss.applyOrientationPolicy();
    } else {
      expect(ss.settings.lockToPortrait.value, isTrue,
          reason:
              'The preceding force-stop must not clear the saved production preference');
      await ss.applyOrientationPolicy();
    }

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SettingsSwitch(
          initialVal: ss.settings.lockToPortrait.value,
          title: 'Lock to Portrait',
          subtitle:
              'Native fixture uses the production persistence and policy callback',
          onChanged: (value) async {
            ss.settings.lockToPortrait.value = value;
            await ss.settings.saveOne('lockToPortrait');
            await ss.applyOrientationPolicy();
          },
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    final lockSwitch = find.text('Lock to Portrait');
    await tester.ensureVisible(lockSwitch);
    expect(lockSwitch, findsOneWidget);

    if (_phase == 'lock') {
      print('E01_LOCK_READY');
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(lockSwitch);
      await tester.pump(const Duration(seconds: 1));
      expect(ss.settings.lockToPortrait.value, isTrue);
      expect(Settings.getSettings().lockToPortrait.value, isTrue);
      print('E01_LOCK_TOGGLED');
      await _observe(tester, 'lock');
      print('E01_LOCK_WAIT_FORCE_STOP');
      // The host force-stops this process after receiving the checkpoint. This
      // is intentionally not a widget-tree restart and must not reach normal
      // test completion in a matrix run.
      await tester.pump(const Duration(seconds: 45));
      fail('Native host did not force-stop the lock fixture');
    }

    if (_phase == 'relaunch') {
      print('E01_RELAUNCH_READY');
      await _observe(tester, 'relaunch');
      print('E01_RELAUNCH_PERSISTED');
      // Disable in the relaunched process. The Flutter integration runner
      // clears its fixture data when a completed run exits, so a third process
      // would not continue this saved-state scenario.
      await tester.tap(lockSwitch);
      await tester.pump(const Duration(seconds: 1));
      expect(ss.settings.lockToPortrait.value, isFalse);
      expect(Settings.getSettings().lockToPortrait.value, isFalse);
      print('E01_UNLOCK_TOGGLED');
      await _observe(tester, 'unlock');
      print('E01_UNLOCK_PERSISTED');
      return;
    }

    fail('Unknown NATIVE_PHASE: $_phase');
  });
}

Future<void> _observe(WidgetTester tester, String scenario) async {
  // The host issues a physical landscape request after each matching ready or
  // toggled checkpoint. This reports Flutter's actual native viewport, which
  // can differ from physical display dimensions when Android letterboxes.
  // Real wall time is needed for Android to process the WindowManager rotation
  // issued by the host; WidgetTester.pump duration advances test time only.
  await Future<void>.delayed(const Duration(seconds: 4));
  await tester.pump();
  final view = tester.view;
  final size = view.physicalSize / view.devicePixelRatio;
  print(
      'E01_VIEWPORT scenario=$scenario width=${size.width.round()} height=${size.height.round()} '
      'portrait=${size.height > size.width} pid=$pid');
}
