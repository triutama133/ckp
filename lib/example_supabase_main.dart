import 'package:flutter/material.dart';
import 'package:catatan_keuangan_pintar/main.dart' as app_main;
import 'package:catatan_keuangan_pintar/services/supabase_init.dart';

/// Example startup which initializes Supabase (if keys supplied) before
/// running the app. Start with:
///
/// flutter run -t lib/example_supabase_main.dart \
///   --dart-define=SUPABASE_URL=https://xyz.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJI...

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();
  runApp(const app_main.MyApp());
}
