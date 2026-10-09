import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/account_access.dart';

void main() {
  test('routing requires a valid server profile', () {
    expect(() => AccountAccess.fromProfile(null), throwsFormatException);
    expect(
      () => AccountAccess.fromProfile({'role': 'owner'}),
      throwsFormatException,
    );
  });
  test('missing rider approval fails closed and server role is retained', () {
    final access = AccountAccess.fromProfile({'role': 'rider'});
    expect(access.role, 'rider');
    expect(access.needsApproval, isTrue);
  });
  test('approved accounts route while revoked accounts require review', () {
    for (final role in ['rider', 'vendor', 'admin']) {
      expect(
        AccountAccess.fromProfile({
          'role': role,
          'verification_status': 'approved',
        }).needsApproval,
        isFalse,
      );
      expect(
        AccountAccess.fromProfile({
          'role': role,
          'verification_status': 'rejected',
        }).needsApproval,
        isTrue,
      );
    }
  });
}
