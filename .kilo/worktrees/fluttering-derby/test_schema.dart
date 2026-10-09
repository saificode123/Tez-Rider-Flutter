import 'dart:io';
import 'dart:convert';

void main() async {
  var client = HttpClient();
  try {
    var request = await client.getUrl(Uri.parse('https://arrqsvejrfdbacfwtpcc.supabase.co/rest/v1/users?limit=1'));
    request.headers.add('apikey', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFycnFzdmVqcmZkYmFjZnd0cGNjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcxMTczODksImV4cCI6MjA5MjY5MzM4OX0.3_0AHeKg5pM8dA9HK6f3merIrfi7SknKRaQ8kByQe7U');
    request.headers.add('Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFycnFzdmVqcmZkYmFjZnd0cGNjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcxMTczODksImV4cCI6MjA5MjY5MzM4OX0.3_0AHeKg5pM8dA9HK6f3merIrfi7SknKRaQ8kByQe7U');
    var response = await request.close();
    var responseBody = await response.transform(utf8.decoder).join();
    print('RESPONSE CODE: ${response.statusCode}');
    print('BODY: $responseBody');
  } finally {
    client.close();
  }
}
