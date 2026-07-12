import 'package:keepass_web/src/entry_payload.dart';
import 'package:test/test.dart';

void main() {
  test('entry payload normalization preserves tags and protection metadata',
      () {
    final normalized = normalizeEntryFieldsPayload(<String, dynamic>{
      'fields': <String, dynamic>{
        'Title': 'Tagged entry',
        'Password': '',
      },
      'custom_data': <String, dynamic>{'otp': 'otpauth://totp/example'},
      'protected': <String, dynamic>{'Title': false, 'Password': true},
      'tags': <dynamic>['work,favorite', 'personal;2fa'],
    });

    expect(normalized['Title'], 'Tagged entry');
    expect(normalized['Password'], '');
    expect(normalized['protected']['Password'], isTrue);
    expect(normalized['custom_data'], isNot(contains('otp')));
    expect(normalized['Tags'], <String>['work', 'favorite', 'personal', '2fa']);
  });
}
