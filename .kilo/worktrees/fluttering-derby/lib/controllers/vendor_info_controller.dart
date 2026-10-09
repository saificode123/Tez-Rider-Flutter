import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One branch/store belonging to a vendor.
class VendorBranch {
  final String name;
  final String address;
  final double? latitude;
  final double? longitude;

  VendorBranch({
    required this.name,
    required this.address,
    this.latitude,
    this.longitude,
  });

  factory VendorBranch.fromJson(Map<String, dynamic> json) {
    return VendorBranch(
      name: (json['name'] ?? '').toString(),
      address: (json['address'] ?? '').toString(),
      latitude: json['latitude'] == null
          ? null
          : double.tryParse(json['latitude'].toString()),
      longitude: json['longitude'] == null
          ? null
          : double.tryParse(json['longitude'].toString()),
    );
  }
}

/// Aggregated info shown on a product card: shop name, rating,
/// and (once we know the customer's location) the nearest branch.
class VendorInfo {
  final String storeName;
  final double? rating;
  final int reviewCount;
  final List<VendorBranch> branches;

  VendorInfo({
    required this.storeName,
    this.rating,
    this.reviewCount = 0,
    this.branches = const [],
  });

  /// Nearest branch to [fromLat]/[fromLng], with its distance in km.
  /// Returns null if this vendor has no branches with coordinates.
  ({VendorBranch branch, double distanceKm})? nearestBranch(
      double? fromLat, double? fromLng) {
    if (fromLat == null || fromLng == null) return null;
    ({VendorBranch branch, double distanceKm})? best;
    for (final b in branches) {
      if (b.latitude == null || b.longitude == null) continue;
      final distMeters = Geolocator.distanceBetween(
          fromLat, fromLng, b.latitude!, b.longitude!);
      final distKm = distMeters / 1000;
      if (best == null || distKm < best.distanceKm) {
        best = (branch: b, distanceKm: distKm);
      }
    }
    return best;
  }
}

class VendorInfoController extends GetxController {
  final _supabase = Supabase.instance.client;

  final RxMap<String, VendorInfo> vendorInfoMap = <String, VendorInfo>{}.obs;
  final Rx<Position?> customerPosition = Rx<Position?>(null);
  final RxBool isLoadingLocation = false.obs;

  VendorInfo? infoFor(String vendorId) => vendorInfoMap[vendorId];

  /// Requests location permission and grabs a single current fix.
  /// Safe to call multiple times — silently no-ops on denial.
  Future<void> loadCustomerLocation() async {
    if (isLoadingLocation.value) return;
    isLoadingLocation.value = true;
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      customerPosition.value = pos;
    } catch (e) {
      debugPrint('VendorInfoController: location fetch failed — $e');
    } finally {
      isLoadingLocation.value = false;
    }
  }

  /// Batch-loads shop name, branches, and rating for a set of vendor
  /// ids in as few round trips as possible. Call this once you have
  /// the distinct vendor ids currently visible (e.g. from the loaded
  /// product list) rather than per-card, to avoid N+1 queries.
  Future<void> loadVendorInfo(Iterable<String> vendorIds) async {
    final ids = vendorIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return;

    final numericIds = ids
        .map((id) => int.tryParse(id))
        .whereType<int>()
        .toList();
    if (numericIds.isEmpty) return;

    try {
      final vendorRows = await _supabase
          .from('vendors')
          .select('user_id, store_name')
          .inFilter('user_id', numericIds);

      final storeRows = await _supabase
          .from('stores')
          .select('vendor_id, name, address, latitude, longitude')
          .inFilter('vendor_id', numericIds);

      Map<int, double> ratingByVendor = {};
      Map<int, int> reviewCountByVendor = {};
      try {
        final ratingRows = await _supabase.rpc(
          'get_vendor_ratings',
          params: {'p_vendor_ids': numericIds},
        ) as List;
        for (final r in ratingRows) {
          final vid = r['vendor_id'];
          if (vid == null) continue;
          final vidInt = vid is int ? vid : int.tryParse(vid.toString());
          if (vidInt == null) continue;
          final avg = r['avg_rating'];
          ratingByVendor[vidInt] =
              avg is num ? avg.toDouble() : double.tryParse(avg?.toString() ?? '') ?? 0;
          reviewCountByVendor[vidInt] =
              int.tryParse(r['review_count']?.toString() ?? '0') ?? 0;
        }
      } catch (e) {
        // RPC missing (migration not run yet) — carry on without ratings.
        debugPrint('VendorInfoController: get_vendor_ratings RPC failed — $e');
      }

      final branchesByVendor = <int, List<VendorBranch>>{};
      for (final row in storeRows) {
        final vid = row['vendor_id'];
        final vidInt = vid is int ? vid : int.tryParse(vid?.toString() ?? '');
        if (vidInt == null) continue;
        branchesByVendor.putIfAbsent(vidInt, () => []).add(VendorBranch.fromJson(row));
      }

      for (final row in vendorRows) {
        final vid = row['user_id'];
        final vidInt = vid is int ? vid : int.tryParse(vid?.toString() ?? '');
        if (vidInt == null) continue;
        final key = vidInt.toString();
        vendorInfoMap[key] = VendorInfo(
          storeName: (row['store_name'] ?? '').toString(),
          rating: ratingByVendor[vidInt],
          reviewCount: reviewCountByVendor[vidInt] ?? 0,
          branches: branchesByVendor[vidInt] ?? const [],
        );
      }
      vendorInfoMap.refresh();
    } catch (e) {
      debugPrint('VendorInfoController: loadVendorInfo failed — $e');
    }
  }
}