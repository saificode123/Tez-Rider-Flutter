import 'package:supabase_flutter/supabase_flutter.dart';

typedef VendorReportReader =
    Future<dynamic> Function(Map<String, dynamic>? after);

class VendorReport {
  VendorReport(
    this.vendorId,
    this.summary,
    this.products,
    this.items,
    this.cursor,
  );
  final int vendorId;
  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> products, items;
  final Map<String, dynamic>? cursor;
  factory VendorReport.parse(dynamic v) {
    if (v is! Map ||
        v['code'] != 'OK' ||
        v['currency'] != 'PKR' ||
        v['vendor_id'] is! int ||
        v['vendor_id'] <= 0 ||
        v['summary'] is! Map ||
        v['top_products'] is! List ||
        v['items'] is! List ||
        v['has_more'] is! bool) {
      throw const FormatException('Vendor report was not confirmed.');
    }
    final summary = Map<String, dynamic>.from(v['summary']);
    for (final key in [
      'total_orders',
      'delivered_orders',
      'amounts_requiring_review',
    ]) {
      if (summary[key] is! int || summary[key] < 0) {
        throw const FormatException('Unconfirmed counts.');
      }
    }
    if (summary['delivered_orders'] > summary['total_orders'] ||
        summary['delivered_sales'] is! num ||
        !(summary['delivered_sales'] as num).isFinite ||
        summary['delivered_sales'] < 0 ||
        summary['status_counts'] is! Map) {
      throw const FormatException('Unconfirmed vendor totals.');
    }
    final products = (v['top_products'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final items = (v['items'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (items.length > 50 || products.length > 5) {
      throw const FormatException('Unbounded report.');
    }
    for (final row in items) {
      if (row['order_id'] is! int ||
          row['order_id'] <= 0 ||
          row['vendor_order_id'] is! int ||
          row['vendor_order_id'] < 0 ||
          row['delivered'] is! bool ||
          row['items'] is! List ||
          row['payment'] is! Map ||
          (row['subtotal'] != null &&
              (row['subtotal'] is! num ||
                  !(row['subtotal'] as num).isFinite ||
                  row['subtotal'] < 0))) {
        throw const FormatException('Unconfirmed order breakdown.');
      }
    }
    Map<String, dynamic>? cursor;
    if (v['has_more']) {
      if (v['next_cursor'] is! Map || items.isEmpty) {
        throw const FormatException('Missing report cursor.');
      }
      cursor = Map<String, dynamic>.from(v['next_cursor']);
      if (cursor.length != 2 ||
          cursor['order_id'] != items.last['order_id'] ||
          cursor['vendor_order_id'] != items.last['vendor_order_id']) {
        throw const FormatException('Invalid report cursor.');
      }
    } else if (v['next_cursor'] != null) {
      throw const FormatException('Unexpected report cursor.');
    }
    return VendorReport(v['vendor_id'], summary, products, items, cursor);
  }
}

class VendorReportService {
  VendorReportService({VendorReportReader? reader, int pageSize = 20})
    : _reader =
          reader ??
          ((after) => Supabase.instance.client
              .rpc(
                'final2_vendor_report',
                params: {'p_after': after, 'p_limit': pageSize},
              )
              .timeout(const Duration(seconds: 15)));
  final VendorReportReader _reader;
  Future<VendorReport> load([Map<String, dynamic>? after]) async =>
      VendorReport.parse(await _reader(after));
}
