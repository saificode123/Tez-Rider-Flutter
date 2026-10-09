import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';

Future<void> main() async {
  print('Connecting to Supabase...');
  try {
    final supabase = SupabaseClient(
      'https://arrqsvejrfdbacfwtpcc.supabase.co',
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFycnFzdmVqcmZkYmFjZnd0cGNjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcxMTczODksImV4cCI6MjA5MjY5MzM4OX0.3_0AHeKg5pM8dA9HK6f3merIrfi7SknKRaQ8kByQe7U',
    );
    print('Connected. Trying a test insert into users table...');
    
    // Attempt a direct insert without auth, just to see what column fails (if RLS allows, or see RLS error)
    final Map<String, dynamic> insertData = {
      'name': 'Test User',
      'email': 'test_direct_insert_${DateTime.now().millisecondsSinceEpoch}@gmail.com',
      'phone': '123456789',
      'role': 'customer',
    };

    final res = await supabase.from('users').insert(insertData).select();
    print('Insert SUCCESS: $res');
  } catch (e) {
    print('\n==================================');
    print('DATABASE ERROR DETAILS:');
    print(e.toString());
    print('==================================\n');
  }
  exit(0);
}
