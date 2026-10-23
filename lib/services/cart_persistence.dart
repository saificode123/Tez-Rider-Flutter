import 'package:supabase_flutter/supabase_flutter.dart';

class SavedCart {
  SavedCart(this.code, this.revision, this.items);
  final String code;
  final int revision;
  final List<Map<String, dynamic>> items;
  factory SavedCart.parse(dynamic value) {
    if (value is! Map ||
        value['revision'] is! int ||
        value['revision'] < 0 ||
        value['items'] is! List ||
        ![
          'OK',
          'ALREADY_APPLIED',
          'CART_CHANGED',
          'UNAVAILABLE',
        ].contains(value['code'])) {
      throw const FormatException('Cart persistence was not confirmed.');
    }
    final items = (value['items'] as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    final ids = <int>{};
    for (final row in items) {
      final id = int.tryParse(row['product_id'].toString());
      if (id == null ||
          id <= 0 ||
          !ids.add(id) ||
          row['qty'] is! int ||
          (row['qty'] as int) < 1 ||
          (row['qty'] as int) > 100 ||
          row['price'] is! num ||
          !(row['price'] as num).isFinite ||
          (row['price'] as num) < 0) {
        throw const FormatException('Saved cart requires review.');
      }
    }
    return SavedCart(value['code'], value['revision'], items);
  }
}

abstract interface class CartPersistence {
  String? get identity;
  Stream<String?> get identityChanges;
  Future<SavedCart> load();
  Future<SavedCart> replace(
    int revision,
    String request,
    List<Map<String, dynamic>> items,
  );
}

class SupabaseCartPersistence implements CartPersistence {
  SupabaseClient get _client => Supabase.instance.client;
  @override
  String? get identity => _client.auth.currentUser?.id;
  @override
  Stream<String?> get identityChanges => _client.auth.onAuthStateChange
      .map((state) => state.session?.user.id)
      .distinct();
  @override
  Future<SavedCart> load() async => SavedCart.parse(
    await _client.rpc('final2_cart_get').timeout(const Duration(seconds: 12)),
  );
  @override
  Future<SavedCart> replace(
    int revision,
    String request,
    List<Map<String, dynamic>> items,
  ) async => SavedCart.parse(
    await _client
        .rpc(
          'final2_cart_replace',
          params: {
            'p_revision': revision,
            'p_request_id': request,
            'p_items': items,
          },
        )
        .timeout(const Duration(seconds: 12)),
  );
}
