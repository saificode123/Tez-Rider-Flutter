import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/prescription_model.dart';
import 'admin_users_service.dart' show blockRequestId;
import 'private_photo_service.dart' show isPrivatePhoto;

typedef PrescriptionRpc =
    Future<dynamic> Function(String, Map<String, dynamic>);

class PrescriptionService {
  PrescriptionService({PrescriptionRpc? call, String? Function()? identity})
    : _call = call ?? _rpc,
      _identity =
          identity ?? (() => Supabase.instance.client.auth.currentUser?.id);
  final PrescriptionRpc _call;
  final String? Function() _identity;
  String? _owner;
  Future<dynamic> _invoke(String name, Map<String, dynamic> body) async {
    final owner = _identity();
    if (owner == null || (_owner != null && owner != _owner)) {
      _pending = null;
      throw StateError('Account changed. Reopen prescriptions.');
    }
    _owner = owner;
    final value = await _call(name, body);
    if (_identity() != owner) {
      _pending = null;
      throw StateError('Account changed. Reopen prescriptions.');
    }
    return value;
  }

  Map<String, dynamic>? _pending;

  static Future<dynamic> _rpc(String name, Map<String, dynamic> body) =>
      Supabase.instance.client
          .rpc(name, params: body)
          .timeout(const Duration(seconds: 20));

  Future<PrescriptionModel?> uploadPrescription({
    required String vendorOrderId,
    required String customerId,
    required String prescriptionImageUrl,
  }) async {
    final order = int.tryParse(vendorOrderId);
    if (order == null || order <= 0 || !isPrivatePhoto(prescriptionImageUrl)) {
      return null;
    }
    final body = {
      'p_vendor_order_id': order,
      'p_reference': prescriptionImageUrl,
    };
    if (_pending != null &&
        (_pending!['p_vendor_order_id'] != order ||
            _pending!['p_reference'] != prescriptionImageUrl)) {
      throw StateError('Retry the original prescription before changing it.');
    }
    _pending ??= {...body, 'p_request_id': blockRequestId()};
    final value = await _invoke(
      'optional_save_prescription',
      Map.from(_pending!),
    );
    if (value is! Map ||
        value['id'] is! int ||
        value['id'] <= 0 ||
        value['vendor_order_id'] != order ||
        value['status'] != 'pending' ||
        value['prescription_image_url'] != prescriptionImageUrl ||
        (customerId.isNotEmpty &&
            value['customer_id'].toString() != customerId)) {
      throw const FormatException(
        'Prescription persistence was not confirmed.',
      );
    }
    final result = PrescriptionModel.fromJson(Map<String, dynamic>.from(value));
    _pending = null;
    return result;
  }

  Future<List<Map<String, dynamic>>> list({int? orderId}) async {
    final value = await _invoke('optional_list_prescriptions', {
      'p_order_id': orderId,
    });
    if (value is! List ||
        value.any(
          (r) =>
              r is! Map ||
              r['id'] is! int ||
              !['pending', 'approved', 'rejected'].contains(r['status']),
        )) {
      throw const FormatException('Prescriptions could not be verified.');
    }
    return value.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<List<PrescriptionModel>> getPrescriptionsByCustomer(
    String customerId,
  ) async => (await list()).map(PrescriptionModel.fromJson).toList();

  Future<List<Map<String, dynamic>>> getPendingPrescriptionsForVendor(
    String vendorId,
  ) => list();

  Future<bool> _review(String id, String status, String? notes) async {
    final parsed = int.tryParse(id);
    if (parsed == null || parsed <= 0) return false;
    final value = await _invoke('optional_review_prescription', {
      'p_id': parsed,
      'p_status': status,
      'p_notes': notes,
    });
    if (value is! Map ||
        value['id'] != parsed ||
        value['status'] != status ||
        value['reviewed_by'] is! int ||
        value['reviewed_at'] is! String) {
      throw const FormatException('Prescription review was not confirmed.');
    }
    return true;
  }

  Future<bool> approvePrescription(String id, String vendorId, String? notes) =>
      _review(id, 'approved', notes);
  Future<bool> rejectPrescription(String id, String vendorId, String reason) =>
      _review(id, 'rejected', reason);
}
