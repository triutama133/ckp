# ckp_temp

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Supabase (see SUPABASE.md)

This repository includes a short Supabase guide in `SUPABASE.md` which
explains how to provide `SUPABASE_URL` and `SUPABASE_ANON_KEY` to the app.

If you prefer a `.env` file for local development (with `flutter_dotenv`),
create a `.env` in the project root containing:

```
SUPABASE_URL=https://xyzcompany.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJI...
```

Then load the env values at startup and call the initializer from
`lib/services/supabase_init.dart` as described in `SUPABASE.md`.

## License

This project is provided as-is for development and experimentation.
# ckp
