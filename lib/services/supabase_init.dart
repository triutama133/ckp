import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Initialize Supabase client with credentials from .env file.
///
/// The .env file should contain:
/// - SUPABASE_URL=https://xxxxx.supabase.co
/// - SUPABASE_ANON_KEY=eyJhbGc...
///
/// Make sure .env is in .gitignore to protect your keys!
Future<void> initSupabase({String? url, String? anonKey}) async {
  // Load from .env file (loaded in main.dart)
  final _url = url ?? dotenv.env['SUPABASE_URL'] ?? '';
  final _anon = anonKey ?? dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  if (_url.isEmpty || _anon.isEmpty) {
    throw Exception(
      'Supabase credentials tidak ditemukan!\n'
      'Pastikan file .env ada dan berisi SUPABASE_URL dan SUPABASE_ANON_KEY'
    );
  }

  await Supabase.initialize(
    url: _url,
    anonKey: _anon,
  );
}
