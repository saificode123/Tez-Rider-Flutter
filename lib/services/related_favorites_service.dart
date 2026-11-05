import 'package:supabase_flutter/supabase_flutter.dart';

typedef RelatedFavoriteRpc = Future<dynamic> Function(
  String,
  Map<String, dynamic>,
);

class RelatedFavoritesService {
  RelatedFavoritesService({
    RelatedFavoriteRpc? rpc,
    String? Function()? identity,
  }) : rpc =
           rpc ??
           ((name, params) => Supabase.instance.client
               .rpc(name, params: params)
               .timeout(const Duration(seconds: 15))),
       identity =
           identity ?? (() => Supabase.instance.client.auth.currentUser?.id);
  final RelatedFavoriteRpc rpc;
  final String? Function() identity;
  String? _owner;
  bool busy = false;
  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> params,
  ) async {
    final owner = identity();
    if (owner == null || (_owner != null && _owner != owner)) {
      throw StateError('Account changed. Open Favorites again.');
    }
    _owner = owner;
    final value = await rpc(name, params);
    if (identity() != owner) {
      throw StateError('Account changed. Open Favorites again.');
    }
    if (value is! Map) {
      throw const FormatException('Favorites were not confirmed.');
    }
    return Map<String, dynamic>.from(value);
  }

  List<Map<String, dynamic>> rows(Map<String, dynamic> value) {
    final items = value['items'];
    if (items is! List || items.length > 100) {
      throw const FormatException('Favorites were not confirmed.');
    }
    return items.map((item) {
      if (item is! Map ||
          !['vendor', 'rider'].contains(item['role']) ||
          item['display_name'] is! String ||
          (item['target_id'] != null &&
              (item['target_id'] is! int || item['target_id'] <= 0))) {
        throw const FormatException('Favorite identity was not confirmed.');
      }
      return Map<String, dynamic>.from(item);
    }).toList();
  }

  Future<List<Map<String, dynamic>>> targets(int orderId) async {
    final items = rows(
      await call('final_customer_order_favorite_targets', {
        'p_order_id': orderId,
      }),
    );
    if (items.any((r) => r['target_id'] == null || r['saved'] is! bool)) {
      throw const FormatException('Favorite state was not confirmed.');
    }
    return items;
  }

  Future<Map<String, dynamic>> load({Map<String, dynamic>? before}) async {
    final result = await call('final_customer_related_favorites', {
      'p_before_at': before?['created_at'],
      'p_before_id': before?['id'],
      'p_limit': 50,
    });
    final items = rows(result);
    if (result['has_more'] is! bool ||
        items.any(
          (r) =>
              r['id'] is! String ||
              r['available'] is! bool ||
              DateTime.tryParse(r['created_at']?.toString() ?? '') == null,
        ) ||
        result['has_more'] == true &&
            (items.isEmpty ||
                result['cursor_id'] != items.last['id'] ||
                result['cursor_at'] != items.last['created_at'])) {
      throw const FormatException('Favorite page was not confirmed.');
    }
    return {...result, 'items': items};
  }

  Future<void> set(int target, String role, bool saved) async {
    if (target <= 0 || !['vendor', 'rider'].contains(role)) {
      throw const FormatException('Choose an authorized Vendor or Rider.');
    }
    if (busy) throw StateError('A favorite change is already in progress.');
    busy = true;
    try {
      final result = await call('final_customer_set_related_favorite', {
        'p_target_id': target,
        'p_role': role,
        'p_saved': saved,
      });
      if (result['target_id'] != target ||
          result['role'] != role ||
          result['saved'] != saved) {
        throw const FormatException('Favorite change was not confirmed.');
      }
    } finally {
      busy = false;
    }
  }

  Future<void> remove(String id) async {
    if (busy) throw StateError('A favorite change is already in progress.');
    busy = true;
    try {
      final result = await call('final_customer_remove_related_favorite', {
        'p_id': id,
      });
      if (result['id'] != id || result['saved'] != false) {
        throw const FormatException('Favorite removal was not confirmed.');
      }
    } finally {
      busy = false;
    }
  }
}
