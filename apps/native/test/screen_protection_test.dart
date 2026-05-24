import 'package:flutter_test/flutter_test.dart';
import 'package:manykee_native/src/services/screen_protection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('setSecure is a no-op on platforms without a native handler', () async {
    // The test host is neither Android, iOS, nor macOS, so this must not
    // throw MissingPluginException even though no MethodChannel handler
    // is registered.
    await expectLater(ScreenProtection.setSecure(true), completes);
    await expectLater(ScreenProtection.setSecure(false), completes);
  });
}
