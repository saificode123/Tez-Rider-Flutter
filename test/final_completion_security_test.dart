import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/storage_service.dart';
import 'package:flutter_application_1/services/account_access.dart';

void main() {
  test(
    'all canonical approved roles restore only their authorized dashboard',
    () {
      for (final role in ['customer', 'vendor', 'rider', 'admin']) {
        final approved = AccountAccess.fromProfile({
          'role': role,
          'verification_status': 'approved',
        });
        expect(approved.dashboardRoute, '/${role}_home');
        final pending = AccountAccess.fromProfile({
          'role': role,
          'verification_status': 'pending',
        });
        expect(
          pending.dashboardRoute,
          role == 'customer' ? '/customer_home' : null,
        );
        final rejected = AccountAccess.fromProfile({
          'role': role,
          'verification_status': 'rejected',
        });
        expect(
          rejected.dashboardRoute,
          role == 'customer' ? '/customer_home' : null,
        );
        expect(
          () => AccountAccess.fromProfile({'role': role, 'is_blocked': true}),
          throwsFormatException,
        );
      }
      expect(
        () => AccountAccess.fromProfile({'role': 'administrator'}),
        throwsFormatException,
      );
      expect(() => AccountAccess.fromProfile(null), throwsFormatException);
    },
  );

  test(
    'legacy media cannot upload, list, sign, delete or create buckets without a trusted workflow',
    () async {
      // No Supabase initialization and a nonexistent file: no network/file access is needed or allowed.
      final service = StorageService();
      final denied = isA<LegacyMediaUnavailable>();
      await expectLater(
        service.uploadPrescriptionImage(
          imageFile: File('not-read.png'),
          customerId: '../other',
          vendorOrderId: '1',
        ),
        throwsA(denied),
      );
      await expectLater(
        service.uploadDocumentImage(
          imageFile: File('not-read.pdf'),
          documentType: 'cnic',
          userId: 'other',
        ),
        throwsA(denied),
      );
      await expectLater(
        service.getPrescriptionDownloadUrl('other/private.png'),
        throwsA(denied),
      );
      await expectLater(
        service.deleteFile('other/private.png', bucket: 'rider-cnic'),
        throwsA(denied),
      );
      await expectLater(
        service.deletePrescriptionImage(
          customerId: 'other',
          fileName: '../private.png',
        ),
        throwsA(denied),
      );
      await expectLater(service.listPrescriptions('other'), throwsA(denied));
      await expectLater(service.initializeStorageBuckets(), throwsA(denied));
    },
  );

  test(
    'product edits preserve stored media while refusing new unvalidated images',
    () {
      const old = 'https://existing.example.test/image.png';
      expect(
        legacyProductMediaAllowed(
          existing: old,
          proposed: old,
          pickedFile: false,
        ),
        isTrue,
      );
      expect(
        legacyProductMediaAllowed(
          existing: old,
          proposed: '',
          pickedFile: false,
        ),
        isTrue,
      );
      for (final url in [
        'https://project.supabase.co/storage/v1/object/public/documents/a.png',
        'javascript:alert(1)',
        'https://example.test/new.png',
      ]) {
        expect(
          legacyProductMediaAllowed(
            existing: old,
            proposed: url,
            pickedFile: false,
          ),
          isFalse,
        );
      }
      expect(
        legacyProductMediaAllowed(
          existing: old,
          proposed: old,
          pickedFile: true,
        ),
        isFalse,
      );
    },
  );
}
