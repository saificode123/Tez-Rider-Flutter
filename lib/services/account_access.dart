/// Routing uses the current server profile, never a selected or cached role.
class AccountAccess {
  AccountAccess.fromProfile(Map<String, dynamic>? profile) {
    if (profile == null ||
        !const {
          'customer',
          'vendor',
          'rider',
          'admin',
        }.contains(profile['role'])) {
      throw const FormatException('Account profile is missing or invalid.');
    }
    role = profile['role'] as String;
    status = profile['verification_status'] as String? ?? 'pending';
  }

  late final String role;
  late final String status;
  bool get needsApproval => role != 'customer' && status != 'approved';
}
