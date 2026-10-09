import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthMiddleware extends GetMiddleware {
  @override
  int? get priority => 1;

  @override
  RouteSettings? redirect(String? route) {
    if (Supabase.instance.client.auth.currentUser == null) {
      return const RouteSettings(name: '/login');
    }

    return null;
  }
}