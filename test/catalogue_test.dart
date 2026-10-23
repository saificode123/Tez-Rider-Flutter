import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/catalogue_service.dart';
import 'package:flutter_application_1/controllers/product_controller.dart';

Map<String, dynamic> product(int id, {String category = 'Food'}) => {
  'id': id,
  'vendor_id': 10,
  'name': 'Product $id',
  'price': 25,
  'category': category,
  'is_available': true,
};
Map<String, dynamic> page(
  List<Map<String, dynamic>> rows, {
  bool more = false,
}) => {
  'items': rows,
  'has_more': more,
  'next_cursor': more
      ? {'id': rows.last['id'], 'name': rows.last['name']}
      : null,
};
void main() {
  test(
    'literal query and exact category remain data in bounded request',
    () async {
      late Map<String, dynamic> request;
      final service = CatalogueService(
        call: (p) async {
          request = p;
          return page([product(1)]);
        },
      );
      await service.load(query: ' literal,*() ', category: 'All', limit: 1);
      expect(request, {
        'p_query': 'literal,*()',
        'p_category': 'All',
        'p_after': null,
        'p_limit': 1,
      });
    },
  );
  for (final invalid in [
    null,
    [],
    {'items': [], 'has_more': true},
    page([product(1), product(1)]),
    page([
      {...product(1), 'price': -1},
    ]),
  ]) {
    test('malformed catalogue never becomes confirmed products: $invalid', () {
      expect(() => CataloguePage.parse(invalid), throwsA(anything));
    });
  }
  test(
    'input limits fail before network and server failures propagate',
    () async {
      var calls = 0;
      final service = CatalogueService(
        call: (_) async {
          calls++;
          throw StateError('offline');
        },
      );
      await expectLater(service.load(query: 'x' * 121), throwsFormatException);
      await expectLater(
        service.load(query: 'bad\nquery'),
        throwsFormatException,
      );
      await expectLater(service.load(limit: 101), throwsFormatException);
      expect(calls, 0);
      await expectLater(service.load(), throwsStateError);
      expect(calls, 1);
    },
  );
  test(
    'category request finds server category beyond earlier page and matches exactly',
    () async {
      final requests = <Map<String, dynamic>>[];
      final controller = ProductController(
        catalogue: CatalogueService(
          call: (p) async {
            requests.add(p);
            return page(
              p['p_category'] == 'Medicine'
                  ? [product(150, category: 'Medicine')]
                  : [product(1)],
            );
          },
        ),
      );
      await controller.refreshProducts();
      await controller.selectCategory('Medicine');
      expect(requests.last['p_category'], 'Medicine');
      expect(controller.products.single.id, '150');
      expect(controller.getProductsByCategory('Med'), isEmpty);
      controller.onClose();
    },
  );
  test(
    'keyset load-more deduplicates and suppresses concurrent duplicate requests',
    () async {
      final pending = Completer<dynamic>();
      var calls = 0;
      Map<String, dynamic>? cursor;
      final controller = ProductController(
        catalogue: CatalogueService(
          call: (p) async {
            calls++;
            if (calls == 1) return page([product(1)], more: true);
            cursor = p['p_after'];
            return pending.future;
          },
        ),
      );
      await controller.refreshProducts();
      final loading = controller.refreshProducts(loadMore: true);
      await controller.refreshProducts(loadMore: true);
      expect(calls, 2);
      expect(cursor, {'id': 1, 'name': 'Product 1'});
      pending.complete(page([product(1), product(2)]));
      await loading;
      expect(controller.products.map((p) => p.id), ['1', '2']);
      expect(controller.hasMore.value, false);
      controller.onClose();
    },
  );
  test('late previous category cannot overwrite current result', () async {
    final old = Completer<dynamic>();
    final controller = ProductController(
      catalogue: CatalogueService(
        call: (p) async => p['p_category'] == null
            ? old.future
            : page([product(2, category: 'Books')]),
      ),
    );
    final first = controller.refreshProducts();
    await controller.selectCategory('Books');
    old.complete(page([product(1)]));
    await first;
    expect(controller.products.single.id, '2');
    expect(controller.isLoading.value, false);
    controller.onClose();
  });
  test(
    'failed refresh exposes error and never retains fabricated or stale products',
    () async {
      var fail = false;
      final controller = ProductController(
        catalogue: CatalogueService(
          call: (_) async {
            if (fail) throw StateError('denied');
            return page([product(1)]);
          },
        ),
      );
      await controller.refreshProducts();
      fail = true;
      await controller.refreshProducts();
      expect(controller.products, isEmpty);
      expect(controller.error.value, isNotNull);
      fail = false;
      await controller.refreshProducts();
      expect(controller.error.value, isNull);
      expect(controller.products.single.id, '1');
      controller.onClose();
    },
  );
  test('category projection rejects malformed responses', () async {
    final good = CatalogueService(
      categoriesCall: () async => [
        {'name': 'Books', 'image_url': null},
      ],
    );
    expect((await good.categories()).single['name'], 'Books');
    await expectLater(
      CatalogueService(
        categoriesCall: () async => [
          {'name': ''},
        ],
      ).categories(),
      throwsFormatException,
    );
  });
}
