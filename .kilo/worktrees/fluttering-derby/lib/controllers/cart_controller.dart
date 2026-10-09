import 'package:get/get.dart';

class CartController extends GetxController {
  RxList<Map<String, dynamic>> cartItems = <Map<String, dynamic>>[].obs;

  void addItem(Map item) {
    final existing = cartItems.indexWhere((e) => e['name'] == item['name']);
    if (existing >= 0) {
      cartItems[existing] = {
        ...cartItems[existing],
        'qty': (cartItems[existing]['qty'] ?? 1) + 1,
      };
    } else {
      cartItems.add({...item, 'qty': 1});
    }
  }

  void removeItem(Map item) => cartItems.removeWhere((e) => e['name'] == item['name']);

  void incrementQty(Map item) {
    final i = cartItems.indexWhere((e) => e['name'] == item['name']);
    if (i >= 0) cartItems[i] = {...cartItems[i], 'qty': cartItems[i]['qty'] + 1};
  }

  void decrementQty(Map item) {
    final i = cartItems.indexWhere((e) => e['name'] == item['name']);
    if (i >= 0) {
      if (cartItems[i]['qty'] <= 1) {
        cartItems.removeAt(i);
      } else {
        cartItems[i] = {...cartItems[i], 'qty': cartItems[i]['qty'] - 1};
      }
    }
  }

  void clear() => cartItems.clear();

  double get totalPrice => cartItems.fold(0, (sum, item) {
    final price = item['price'];
    final p = price is num ? price.toDouble() : double.tryParse(price?.toString() ?? '0') ?? 0.0;
    return sum + (p * (item['qty'] ?? 1));
  });

  int get totalItems => cartItems.fold(0, (sum, item) => sum + (item['qty'] as int? ?? 1));
}