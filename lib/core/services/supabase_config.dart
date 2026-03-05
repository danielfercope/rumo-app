import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const String url = 'https://yfupsbsfktkekdabvewk.supabase.co';
  static const String anonKey = '***SUPABASE_SERVICE_ROLE_KEY_REMOVIDA***';

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}