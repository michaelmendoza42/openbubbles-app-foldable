import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Infrastructure smoke tests only. These do not exercise OpenBubbles policy or
// prove that an Android/iPad OS honors orientation requests.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('Flutter sends an upright portrait request through the platform channel',
      () async {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    expect(calls, hasLength(1));
    expect(calls.single.method, 'SystemChrome.setPreferredOrientations');
    expect(calls.single.arguments, ['DeviceOrientation.portraitUp']);
  });

  test('Flutter can send the existing user-controlled orientation combination',
      () async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.portraitUp,
    ]);

    expect(calls, hasLength(1));
    expect(calls.single.method, 'SystemChrome.setPreferredOrientations');
    expect(calls.single.arguments, [
      'DeviceOrientation.landscapeRight',
      'DeviceOrientation.landscapeLeft',
      'DeviceOrientation.portraitUp',
    ]);
  });
}
