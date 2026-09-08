import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/settings/services/trusted_contact_service.dart';

void main() {
  group('TrustedContactService phone validation', () {
    test(
      'normalizes dialable punctuation without requesting call permission',
      () {
        expect(
          TrustedContactService.normalizePhone('+91 (98765) 43210'),
          '+919876543210',
        );
        expect(
          TrustedContactService.normalizePhone('555-123-4567'),
          '5551234567',
        );
      },
    );

    test('rejects empty, short, alphabetic, and overlong numbers', () {
      expect(TrustedContactService.normalizePhone(''), isNull);
      expect(TrustedContactService.normalizePhone('12345'), isNull);
      expect(TrustedContactService.normalizePhone('CALL-ME'), isNull);
      expect(TrustedContactService.normalizePhone('1234567890123456'), isNull);
    });
  });
}
