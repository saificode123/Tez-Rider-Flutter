import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminMiddleware extends GetMiddleware {
  @override
  int? get priority => 2; // Run after AuthMiddleware

  @override
  RouteSettings? redirect(String? route) {
    if (Supabase.instance.client.auth.currentUser == null) return null;

    return null; // The async check happens in GetPage onInit or inside the widget
  }
}