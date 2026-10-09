import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/prescription_model.dart';

class PrescriptionService {
  final _supabase = Supabase.instance.client;

  /// Upload Prescription
  Future<PrescriptionModel?> uploadPrescription({
    required String vendorOrderId,
    required String customerId,
    required String prescriptionImageUrl,
  }) async {
    try {
      // Get vendor id from vendor_orders table
      final vendorOrder = await _supabase
          .from('vendor_orders')
          .select('vendor_id')
          .eq('id', int.parse(vendorOrderId))
          .single();

      final vendorId = vendorOrder['vendor_id'];

      final response = await _supabase
          .from('prescriptions')
          .insert({
            'vendor_order_id': int.parse(vendorOrderId),
            'customer_id': int.parse(customerId),
            'vendor_id': vendorId,
            'prescription_image_url': prescriptionImageUrl,
            'status': 'pending',
            'uploaded_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();

      return PrescriptionModel.fromJson(response);
    } catch (e) {
      print('uploadPrescription Error: $e');
      return null;
    }
  }

  /// Fetch prescriptions uploaded by a customer
  Future<List<PrescriptionModel>> getPrescriptionsByCustomer(
      String customerId) async {
    try {
      final response = await _supabase
          .from('prescriptions')
          .select()
          .eq('customer_id', int.parse(customerId))
          .order('uploaded_at', ascending: false);

      return response
          .map<PrescriptionModel>(
            (item) => PrescriptionModel.fromJson(item),
          )
          .toList();
    } catch (e) {
      print('getPrescriptionsByCustomer Error: $e');
      return [];
    }
  }  /// Fetch pending prescriptions for a vendor
  Future<List<Map<String, dynamic>>> getPendingPrescriptionsForVendor(
      String vendorId) async {
    try {
      final response = await _supabase
          .from('prescriptions')
          .select()
          .eq('vendor_id', int.parse(vendorId))
          .eq('status', 'pending')
          .order('uploaded_at', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('getPendingPrescriptionsForVendor Error: $e');
      return [];
    }
  }

  /// Approve Prescription
  Future<bool> approvePrescription(
    String prescriptionId,
    String vendorId,
    String? notes,
  ) async {
    try {
      await _supabase
          .from('prescriptions')
          .update({
            'status': 'approved',
            'vendor_notes': notes,
            'reviewed_at': DateTime.now().toIso8601String(),
            'reviewed_by': int.parse(vendorId),
          })
          .eq('id', int.parse(prescriptionId))
          .eq('vendor_id', int.parse(vendorId));

      return true;
    } catch (e) {
      print('approvePrescription Error: $e');
      return false;
    }
  }  /// Reject Prescription
  Future<bool> rejectPrescription(
    String prescriptionId,
    String vendorId,
    String reason,
  ) async {
    try {
      await _supabase
          .from('prescriptions')
          .update({
            'status': 'rejected',
            'vendor_notes': reason,
            'reviewed_at': DateTime.now().toIso8601String(),
            'reviewed_by': int.parse(vendorId),
          })
          .eq('id', int.parse(prescriptionId))
          .eq('vendor_id', int.parse(vendorId));

      return true;
    } catch (e) {
      print('rejectPrescription Error: $e');
      return false;
    }
  }
}