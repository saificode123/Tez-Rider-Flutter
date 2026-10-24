import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_users_service.dart' show blockRequestId;

const outOfStockMessage = 'This product is currently out of stock.';

class ProductStock {
  ProductStock(Map<String, dynamic> row)
    : quantity = (row['stock_qty'] as num?)?.toInt() ?? 0,
      threshold = (row['low_stock_threshold'] as num?)?.toInt() ?? 5,
      version = (row['stock_version'] as num?)?.toInt() ?? 0,
      confirmed = row['stock_confirmed'] == true,
      available = row['is_available'] == true;
  final int quantity, threshold, version;
  final bool confirmed, available;
  bool get purchasable => available && confirmed && quantity > 0;
  String get label => !confirmed
      ? 'Stock confirmation required'
      : quantity == 0
      ? 'Out of stock'
      : !available
      ? 'Unavailable'
      : quantity <= threshold
      ? 'Low stock'
      : 'In stock';
  static int? nonnegativeInteger(String text) {
    if (!RegExp(r'^\d+$').hasMatch(text.trim())) return null;
    final value = int.tryParse(text.trim());
    return value != null && value <= 1000000000 ? value : null;
  }
}

typedef InventoryReader =
    Future<List<Map<String, dynamic>>> Function(List<int> ids);
typedef InventoryWriter =
    Future<Map<String, dynamic>> Function(
      String rpc,
      Map<String, dynamic> params,
    );

class InventoryApi {
  static Future<List<Map<String, dynamic>>> read(List<int> ids) async {
    if (ids.isEmpty) return [];
    if (ids.length > 100) {
      throw StateError('Review your cart before continuing.');
    }
    return List<Map<String, dynamic>>.from(
      await Supabase.instance.client
          .from('products')
          .select(
            'id,name,price,vendor_id,image_url,is_available,stock_qty,low_stock_threshold,stock_confirmed,stock_version',
          )
          .inFilter('id', ids)
          .limit(100)
          .timeout(const Duration(seconds: 12)),
    );
  }

  static Future<Map<String, dynamic>> write(
    String rpc,
    Map<String, dynamic> params,
  ) async => Map<String, dynamic>.from(
    await Supabase.instance.client
            .rpc(rpc, params: params)
            .timeout(const Duration(seconds: 15))
        as Map,
  );
}

/// Retries an uncertain write with the identical UUID and payload. A definitive
/// conflict clears the request so the vendor can reload and confirm a new count.
class InventoryWriteFlow {
  InventoryWriteFlow({InventoryWriter? writer})
    : writer = writer ?? InventoryApi.write;
  final InventoryWriter writer;
  bool busy = false;
  Map<String, dynamic>? _pending;
  bool get hasPending => _pending != null;
  Future<Map<String, dynamic>> save(
    String rpc,
    Map<String, dynamic> params,
  ) async {
    if (busy) throw StateError('An inventory update is already in progress.');
    final payload =
        jsonDecode(jsonEncode({'rpc': rpc, 'params': params}))
            as Map<String, dynamic>;
    if (_pending != null &&
        jsonEncode(_pending!['payload']) != jsonEncode(payload)) {
      throw StateError(
        'The previous inventory result is uncertain. Retry its original values before editing.',
      );
    }
    _pending ??= {'request_id': blockRequestId(), 'payload': payload};
    busy = true;
    try {
      final saved = Map<String, dynamic>.from(
        (_pending!['payload'] as Map)['params'] as Map,
      );
      final result = await writer(rpc, {
        ...saved,
        'p_request_id': _pending!['request_id'],
      });
      if ([
        'UPDATED',
        'ALREADY_UPDATED',
        'STOCK_CHANGED',
        'FORBIDDEN',
        'PRODUCT_REMOVED',
      ].contains(result['code'])) {
        _pending = null;
      }
      return result;
    } on PostgrestException catch (e) {
      if (['22023', '42501', '23514'].contains(e.code)) _pending = null;
      rethrow;
    } finally {
      busy = false;
    }
  }
}
