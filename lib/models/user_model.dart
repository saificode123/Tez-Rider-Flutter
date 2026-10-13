class UserModel {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final String role;
  final String verificationStatus;
  final String? profileImage;
  final String? cnic;
  final String? cnicImageUrl;
  final String? rejectionReason;
  final bool documentValid;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    required this.role,
    required this.verificationStatus,
    this.profileImage,
    this.cnic,
    this.cnicImageUrl,
    this.rejectionReason,
    this.documentValid = false,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? 'Unknown',
      email: json['email'] ?? '',
      phone: json['phone'],
      role: json['role'] ?? 'customer',
      verificationStatus: json['verification_status'] ?? 'pending',
      profileImage: json['profile_image'],
      cnic: json['cnic_masked'] ?? json['cnic'],
      cnicImageUrl: json['cnic_image_url'],
      rejectionReason: json['rejection_reason'],
      documentValid: json['document_valid'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'role': role,
      'verification_status': verificationStatus,
      'profile_image': profileImage,
      'cnic': cnic,
      'cnic_image_url': cnicImageUrl,
      'rejection_reason': rejectionReason,
    };
  }

  UserModel copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    String? role,
    String? verificationStatus,
    String? profileImage,
    String? cnic,
    String? cnicImageUrl,
    String? rejectionReason,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      profileImage: profileImage ?? this.profileImage,
      cnic: cnic ?? this.cnic,
      cnicImageUrl: cnicImageUrl ?? this.cnicImageUrl,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      documentValid: documentValid,
    );
  }
}
