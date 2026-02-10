# Supabase setup (for ckp_temp)

This document describes how to quickly enable Supabase as a remote provider for
group membership and invites.

1) Create a Supabase project

- Visit https://app.supabase.com and create a new project.
- In project settings, copy the `API URL` and the `anon` public key.

2) Provide keys to the app

Two common approaches:

A) Use `--dart-define` (no extra packages required)

```bash
flutter run -t lib/example_supabase_main.dart \
  --dart-define=SUPABASE_URL=https://xyzcompany.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJI...
```

B) Use `flutter_dotenv` and a `.env` file (recommended for local development)

- Add `flutter_dotenv` to `pubspec.yaml` dependencies.
- Create a `.env` at project root with `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
- In code, load dotenv and call `initSupabase(url: env['SUPABASE_URL'], anonKey: env['SUPABASE_ANON_KEY'])`.

3) Files in this repo

- `lib/services/supabase_init.dart` — helper `initSupabase()` which reads
  values from `String.fromEnvironment` (suitable for `--dart-define`) or
  accepts them as parameters.
- `lib/example_supabase_main.dart` — example `main()` which calls the
  initializer before starting the app.

4) Security & production

- For production, prefer server-side security and avoid shipping secret keys in
  client builds. Supabase anon keys are scoped but still should be rotated and
  protected for sensitive flows.
- Enable Row Level Security (RLS) and create policies that match your group's
  membership model if you plan to rely on Supabase for enforcement.

5) Next steps

- Configure Supabase tables to mirror `groups`, `group_members`, and
  `group_invites` if you want remote persistence. You can create simple SQL
  migrations from `tools/server/db.sql` (the repo contains a VPS scaffold).

6) Push notifications (optional)

- Create table `device_tokens` and store FCM tokens per user.
- Deploy Edge Function `send_push` in `supabase/functions/send_push`.
- Set env vars on Supabase:
  - `SUPABASE_URL`
  - `SUPABASE_SERVICE_ROLE_KEY`
  - `FCM_SERVER_KEY`
