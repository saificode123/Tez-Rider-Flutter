class PrescriptionModel {
  final String? id;
  final String? vendorOrderId;
  final String? customerId;
  final String prescriptionImageUrl;
  final String status; // pending, approved, rejected
  final String? vendorNotes;
  final DateTime? uploadedAt;
  final DateTime? reviewedAt;
  final String? reviewedBy;

  PrescriptionModel({
    this.id,
    this.vendorOrderId,
    this.customerId,
    required this.prescriptionImageUrl,
    this.status = 'pending',
    this.vendorNotes,
    this.uploadedAt,
    this.reviewedAt,
    this.reviewedBy,
  });

  factory PrescriptionModel.fromJson(Map<String, dynamic> json) {
    return PrescriptionModel(
      id: json['id']?.toString(),
      vendorOrderId: json['vendor_order_id']?.toString(),
      customerId: json['customer_id']?.toString(),
      prescriptionImageUrl: json['prescription_image_url'] ?? '',
      status: json['status'] ?? 'pending',
      vendorNotes: json['vendor_notes'],
      uploadedAt: json['uploaded_at'] != null ? DateTime.parse(json['uploaded_at']) : null,
      reviewedAt: json['reviewed_at'] != null ? DateTime.parse(json['reviewed_at']) : null,
      reviewedBy: json['reviewed_by']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'vendor_order_id': vendorOrderId,
      'customer_id': customerId,
      'prescription_image_url': prescriptionImageUrl,
      'status': status,
      'vendor_notes': vendorNotes,
      'uploaded_at': uploadedAt?.toIso8601String(),
      'reviewed_at': reviewedAt?.toIso8601String(),
      'reviewed_by': reviewedBy,
    };
  }

  PrescriptionModel copyWith({
    String? id,
    String? vendorOrderId,
    String? customerId,
    String? prescriptionImageUrl,
    String? status,
    String? vendorNotes,
    DateTime? uploadedAt,
    DateTime? reviewedAt,
    String? reviewedBy,
  }) {
    return PrescriptionModel(
      id: id ?? this.id,
      vendorOrderId: vendorOrderId ?? this.vendorOrderId,
      customerId: customerId ?? this.customerId,
      prescriptionImageUrl: prescriptionImageUrl ?? this.prescriptionImageUrl,
      status: status ?? this.status,
      vendorNotes: vendorNotes ?? this.vendorNotes,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      reviewedBy: reviewedBy ?? this.reviewedBy,
    );
  }

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
}
