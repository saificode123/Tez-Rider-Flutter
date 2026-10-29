import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads only through existing authenticated RLS. Never persists addresses or
/// coordinates, infers an unconfirmed destination, or changes an order.
class DeliveryMapStops {
  const DeliveryMapStops({this.pickup, this.destination, this.status = ''});
  final LatLng? pickup, destination;
  final String status;
  static LatLng? point(dynamic lat, dynamic lng) {
    if (lat is! num ||
        lng is! num ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat.abs() > 90 ||
        lng.abs() > 180) {
      return null;
    }
    return LatLng(lat.toDouble(), lng.toDouble());
  }

  static Future<DeliveryMapStops> load(SupabaseClient client, int id) async {
    final owner = client.auth.currentUser?.id;
    if (owner == null || id < 1) throw StateError('Sign in required');
    void check() {
      if (client.auth.currentUser?.id != owner) {
        throw StateError('Account changed');
      }
    }

    final order = await client
        .from('orders')
        .select(
          'id,order_status,delivery_lat,delivery_lng,destination_confirmed_at',
        )
        .eq('id', id)
        .maybeSingle()
        .timeout(const Duration(seconds: 8));
    check();
    if (order == null) throw StateError('Order unavailable');
    final status = order['order_status'] as String? ?? '';
    if (['delivered', 'cancelled'].contains(status)) {
      return DeliveryMapStops(status: status);
    }
    final portions = await client
        .from('vendor_orders')
        .select('vendor_id')
        .eq('order_id', id)
        .order('id')
        .limit(1)
        .timeout(const Duration(seconds: 8));
    check();
    LatLng? pickup;
    if (portions.isNotEmpty) {
      final vendor = await client
          .from('vendors')
          .select('latitude,longitude')
          .eq('user_id', portions.first['vendor_id'])
          .maybeSingle()
          .timeout(const Duration(seconds: 8));
      check();
      pickup = point(vendor?['latitude'], vendor?['longitude']);
    }
    return DeliveryMapStops(
      pickup: pickup,
      destination: order['destination_confirmed_at'] == null
          ? null
          : point(order['delivery_lat'], order['delivery_lng']),
      status: status,
    );
  }
}

Future<Map<String, dynamic>> fetchDeliveryRoadRoute(
  int id, {
  bool pickup = false,
}) async {
  try {
    final response = await Supabase.instance.client.functions
        .invoke(
          'get-delivery-route',
          body: {'orderId': id, if (pickup) 'target': 'pickup'},
        )
        .timeout(const Duration(seconds: 20));
    if (response.data is! Map) throw const FormatException('Invalid route');
    return Map<String, dynamic>.from(response.data as Map);
  } on FunctionException catch (error) {
    if (error.details is Map) {
      return Map<String, dynamic>.from(error.details as Map);
    }
    return {
      'code': error.status == 401
          ? 'UNAUTHORIZED'
          : error.status == 403
          ? 'FORBIDDEN'
          : 'UNAVAILABLE',
    };
  }
}
