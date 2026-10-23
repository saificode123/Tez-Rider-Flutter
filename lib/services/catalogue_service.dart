import 'package:supabase_flutter/supabase_flutter.dart';

class CataloguePage {
  const CataloguePage(this.items, this.hasMore, this.cursor);
  final List<Map<String, dynamic>> items;
  final bool hasMore;
  final Map<String, dynamic>? cursor;
  factory CataloguePage.parse(dynamic value) {
    if (value is! Map ||
        value['items'] is! List ||
        value['has_more'] is! bool) {
      throw const FormatException('Catalogue response was not confirmed.');
    }
    final items = (value['items'] as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    final ids = <num>{};
    for (final row in items) {
      if (row['id'] is! num ||
          (row['id'] as num) <= 0 ||
          row['vendor_id'] is! num ||
          (row['vendor_id'] as num) <= 0 ||
          row['name'] is! String ||
          row['price'] is! num ||
          !(row['price'] as num).isFinite ||
          (row['price'] as num) < 0 ||
          !ids.add(row['id'] as num)) {
        throw const FormatException('Catalogue product was not confirmed.');
      }
      row['is_available'] = row['is_available'] == true;
    }
    final more = value['has_more'] as bool;
    final cursor = value['next_cursor'];
    if (more &&
        (items.isEmpty ||
            cursor is! Map ||
            cursor['id'] is! num ||
            cursor['name'] is! String)) {
      throw const FormatException('Catalogue page cursor was not confirmed.');
    }
    return CataloguePage(
      items,
      more,
      cursor is Map ? Map<String, dynamic>.from(cursor) : null,
    );
  }
}

typedef CatalogueCall = Future<dynamic> Function(Map<String, dynamic>);

class CatalogueService {
  CatalogueService({
    CatalogueCall? call,
    Future<dynamic> Function()? categoriesCall,
  }) : _call =
           call ??
           ((params) => Supabase.instance.client
               .rpc('final2_catalog', params: params)
               .timeout(const Duration(seconds: 12))),
       _categoriesCall =
           categoriesCall ??
           (() => Supabase.instance.client
               .rpc('final2_catalog_categories')
               .timeout(const Duration(seconds: 12)));
  final CatalogueCall _call;
  final Future<dynamic> Function() _categoriesCall;
  Future<List<Map<String, dynamic>>> categories() async {
    final value = await _categoriesCall();
    if (value is! List) {
      throw const FormatException('Categories were not confirmed.');
    }
    return value.map((row) {
      final item = Map<String, dynamic>.from(row as Map);
      if (item['name'] is! String || (item['name'] as String).trim().isEmpty) {
        throw const FormatException('Category was not confirmed.');
      }
      return item;
    }).toList();
  }

  Future<CataloguePage> load({
    String query = '',
    String? category,
    Map<String, dynamic>? after,
    int limit = 40,
  }) async {
    if (query.trim().runes.length > 120 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(query) ||
        (category != null &&
            (category.trim().runes.length > 80 ||
                RegExp(r'[\x00-\x1f\x7f]').hasMatch(category))) ||
        limit < 1 ||
        limit > 100) {
      throw const FormatException('Use up to 120 characters for search.');
    }
    return CataloguePage.parse(
      await _call({
        'p_query': query.trim(),
        'p_category': category,
        'p_after': after,
        'p_limit': limit,
      }),
    );
  }
}
