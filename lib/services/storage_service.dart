import 'dart:io';

/// Legacy buckets have no authorized upload/read workflow on TEST.
/// Do not restore direct Storage access when a bucket or grant is later added.
/// CNIC, dispute evidence and invoice services use separate trusted APIs.
class LegacyMediaUnavailable implements Exception {
  const LegacyMediaUnavailable();
  @override
  String toString() =>
      'Secure media access is not configured. No file was uploaded or changed.';
}

bool legacyProductMediaAllowed({
  required String existing,
  required String proposed,
  required bool pickedFile,
}) =>
    !pickedFile &&
    (proposed.trim().isEmpty || proposed.trim() == existing.trim());

class StorageService {
  Future<String?> uploadPrescriptionImage({
    required File imageFile,
    required String customerId,
    required String vendorOrderId,
  }) async => throw const LegacyMediaUnavailable();

  Future<String?> uploadDocumentImage({
    required File imageFile,
    required String documentType,
    required String userId,
  }) async => throw const LegacyMediaUnavailable();

  Future<bool> deleteFile(
    String filePath, {
    String bucket = 'prescriptions',
  }) async => throw const LegacyMediaUnavailable();

  Future<bool> deletePrescriptionImage({
    required String customerId,
    required String fileName,
  }) async => throw const LegacyMediaUnavailable();

  Future<List<String>> listPrescriptions(String customerId) async =>
      throw const LegacyMediaUnavailable();

  Future<void> initializeStorageBuckets() async =>
      throw const LegacyMediaUnavailable();

  Future<String?> getPrescriptionDownloadUrl(String filePath) async =>
      throw const LegacyMediaUnavailable();
}
