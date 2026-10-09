import 'package:supabase/supabase.dart';

void main() async {
  final supabase = SupabaseClient(
    'https://arrqsvejrfdbacfwtpcc.supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFycnFzdmVqcmZkYmFjZnd0cGNjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcxMTczODksImV4cCI6MjA5MjY5MzM4OX0.3_0AHeKg5pM8dA9HK6f3merIrfi7SknKRaQ8kByQe7U',
  );

  try {
    print('--- DB DIAGNOSTICS ---');
    print('Testing SELECT on users table...');
    final data = await supabase.from('users').select();
    print('Success! Users found: ${data.length}');
    for (var u in data) {
      print(u);
    }
    
    print('Testing SELECT on products table...');
    final pData = await supabase.from('products').select();
    print('Success! Products found: ${pData.length}');
    
  } catch (e) {
    print('❌ ERROR DETAILS: $e');
  }
}
