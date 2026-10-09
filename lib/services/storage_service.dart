import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as path;

class StorageService {
  final _supabase = Supabase.instance.client;

  /// Upload prescription image to Supabase Storage
  /// Returns the public URL of the uploaded image
  Future<String?> uploadPrescriptionImage({
    required File imageFile,
    required String customerId,
    required String vendorOrderId,
  }) async {
    try {
      final fileName =
          'prescription_${customerId}_${vendorOrderId}_${DateTime.now().millisecondsSinceEpoch}.${path.extension(imageFile.path).replaceFirst('.', '')}';
      final filePath = 'prescriptions/$customerId/$fileName';

      // Upload to Supabase Storage bucket 'prescriptions'
      await _supabase.storage.from('prescriptions').upload(
        filePath,
        imageFile,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
      );

      // Get public URL
      final publicUrl =
          _supabase.storage.from('prescriptions').getPublicUrl(filePath);

      return publicUrl;
    } catch (e) {
      print('StorageService uploadPrescriptionImage error: $e');
      return null;
    }
  }

  /// Upload other document images (general purpose)
  Future<String?> uploadDocumentImage({
    required File imageFile,
    required String documentType, // e.g., 'prescription', 'id', 'proof'
    required String userId,
  }) async {
    try {
      final fileName =
          '${documentType}_${userId}_${DateTime.now().millisecondsSinceEpoch}.${path.extension(imageFile.path).replaceFirst('.', '')}';
      final filePath = 'documents/$documentType/$userId/$fileName';

      await _supabase.storage.from('documents').upload(
        filePath,
        imageFile,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
      );

      final publicUrl =
          _supabase.storage.from('documents').getPublicUrl(filePath);

      return publicUrl;
    } catch (e) {
      print('StorageService uploadDocumentImage error: $e');
      return null;
    }
  }

  /// Delete file from storage
  Future<bool> deleteFile(String filePath, {String bucket = 'prescriptions'}) async {
    try {
      await _supabase.storage.from(bucket).remove([filePath]);
      return true;
    } catch (e) {
      print('StorageService deleteFile error: $e');
      return false;
    }
  }

  /// Delete prescription by constructing path
  Future<bool> deletePrescriptionImage({
    required String customerId,
    required String fileName,
  }) async {
    try {
      final filePath = 'prescriptions/$customerId/$fileName';
      return await deleteFile(filePath, bucket: 'prescriptions');
    } catch (e) {
      print('StorageService deletePrescriptionImage error: $e');
      return false;
    }
  }

  /// Get list of prescriptions uploaded by user
  Future<List<String>> listPrescriptions(String customerId) async {
    try {
      final files =
          await _supabase.storage.from('prescriptions').list(path: 'prescriptions/$customerId');
      return files.map((f) => f.name).toList();
    } catch (e) {
      print('StorageService listPrescriptions error: $e');
      return [];
    }
  }

  /// Create storage buckets (Run once during app initialization)
  Future<void> initializeStorageBuckets() async {
    try {
      // Check if buckets exist, create if not
      final buckets = await _supabase.storage.listBuckets();
      final bucketNames = buckets.map((b) => b.name).toList();

      // Create prescriptions bucket if not exists
      if (!bucketNames.contains('prescriptions')) {
        await _supabase.storage.createBucket('prescriptions', const BucketOptions(
          public: false,
          allowedMimeTypes: ['image/jpeg', 'image/png', 'image/webp', 'application/pdf'],
        ));
        print('Created prescriptions bucket');
      }

      // Create documents bucket if not exists
      if (!bucketNames.contains('documents')) {
        await _supabase.storage.createBucket('documents', const BucketOptions(
          public: false,
          allowedMimeTypes: ['image/jpeg', 'image/png', 'image/webp', 'application/pdf'],
        ));
        print('Created documents bucket');
      }
    } catch (e) {
      print('StorageService initializeStorageBuckets error: $e');
    }
  }

  /// Get download URL for a prescription
  Future<String?> getPrescriptionDownloadUrl(String filePath) async {
    try {
      return _supabase.storage.from('prescriptions').getPublicUrl(filePath);
    } catch (e) {
      print('StorageService getPrescriptionDownloadUrl error: $e');
      return null;
    }
  }
}
