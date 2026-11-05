import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../services/related_favorites_service.dart';

/// Existing order history supplies targets; the server independently checks it.
class RelatedFavorites extends StatefulWidget {
  const RelatedFavorites({super.key, this.orderId, this.service});
  final int? orderId;
  final RelatedFavoritesService? service;
  @override
  State<RelatedFavorites> createState() => _RelatedFavoritesState();
}

class _RelatedFavoritesState extends State<RelatedFavorites> {
  late final service = widget.service ?? RelatedFavoritesService();
  List<Map<String, dynamic>> items = [];
  bool loading = true, changing = false, more = false;
  String? error;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  Future<void> load({bool append = false}) async {
    final request = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final page = widget.orderId == null
          ? await service.load(
              before: append && items.isNotEmpty ? items.last : null,
            )
          : null;
      final rows = page == null
          ? await service.targets(widget.orderId!)
          : List<Map<String, dynamic>>.from(page['items']);
      if (!mounted || request != generation) return;
      setState(() {
        if (append) {
          final ids = items.map((i) => i['id']).toSet();
          items.addAll(rows.where((r) => ids.add(r['id'])));
        } else {
          items = rows;
        }
        more = page?['has_more'] == true;
      });
    } catch (_) {
      if (mounted && request == generation) {
        setState(() => error = 'Favorites could not be loaded. Please retry.');
      }
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  Future<void> change(Map<String, dynamic> item) async {
    if (changing) return;
    setState(() {
      changing = true;
      error = null;
    });
    try {
      if (widget.orderId == null) {
        await service.remove(item['id'] as String);
      } else {
        await service.set(
          item['target_id'] as int,
          item['role'] as String,
          item['saved'] != true,
        );
      }
      if (mounted) await load();
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'The change was not confirmed. Check your connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => changing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (loading || changing) const LinearProgressIndicator(),
      if (error != null) ...[
        Text(error!.tr, semanticsLabel: error!.tr),
        TextButton(
          onPressed: loading || changing ? null : () => load(),
          child: Text('Retry'.tr),
        ),
      ],
      if (!loading && error == null && items.isEmpty)
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            (widget.orderId == null
                    ? 'No Favorites'
                    : 'No eligible Vendors or Riders for this order.')
                .tr,
          ),
        ),
      for (final item in items)
        ListTile(
          leading: Icon(
            item['role'] == 'vendor'
                ? Icons.storefront_rounded
                : Icons.delivery_dining_rounded,
          ),
          title: Text(
            item['display_name'] == 'Unavailable'
                ? 'Unavailable'.tr
                : item['display_name'] as String,
          ),
          subtitle: Text((item['role'] == 'vendor' ? 'Vendor' : 'Rider').tr),
          trailing: IconButton(
            tooltip:
                (widget.orderId == null || item['saved'] == true
                        ? 'Remove from Favorites'
                        : 'Add to Favorites')
                    .tr,
            onPressed: loading || changing ? null : () => change(item),
            icon: Icon(
              widget.orderId == null || item['saved'] == true
                  ? Icons.favorite
                  : Icons.favorite_border,
            ),
          ),
        ),
      if (more)
        TextButton(
          onPressed: loading || changing ? null : () => load(append: true),
          child: Text('Load more'.tr),
        ),
    ],
  );
}
