-- =========================================================
-- MIGRATION SCRIPT - JALANKAN INI DI SUPABASE SQL EDITOR
-- =========================================================
-- Fix: "Could not find column in schema cache" errors
-- Status: REQUIRED untuk sync berfungsi

-- 1. Add missing columns yang ada di local tapi tidak di Supabase
ALTER TABLE public.gold_holdings
ADD COLUMN IF NOT EXISTS purchase_price numeric DEFAULT NULL;

ALTER TABLE public.gold_holdings
ADD COLUMN IF NOT EXISTS scope text DEFAULT 'personal';

ALTER TABLE public.gold_holdings
ADD COLUMN IF NOT EXISTS group_id text DEFAULT NULL;

ALTER TABLE public.goals
ADD COLUMN IF NOT EXISTS completed_at timestamp with time zone DEFAULT NULL;

ALTER TABLE public.gold_transactions
ADD COLUMN IF NOT EXISTS scope text DEFAULT 'personal';

ALTER TABLE public.gold_transactions
ADD COLUMN IF NOT EXISTS group_id text DEFAULT NULL;

-- 2. Add user_id untuk Row Level Security (jika belum ada)
ALTER TABLE public.accounts
ADD COLUMN IF NOT EXISTS user_id text DEFAULT NULL;

ALTER TABLE public.goals  
ADD COLUMN IF NOT EXISTS user_id text DEFAULT NULL;

ALTER TABLE public.transactions
ADD COLUMN IF NOT EXISTS user_id text DEFAULT NULL;

ALTER TABLE public.categories
ADD COLUMN IF NOT EXISTS user_id text DEFAULT NULL;

-- =========================================================
-- FIX FOREIGN KEY ERRORS - USER PROFILE ISSUES
-- =========================================================

-- MASALAH: Messages/transactions merujuk ke user_id yang tidak ada di public.users
-- SOLUSI: Create user profile untuk semua authenticated users

-- A. Insert missing user profiles dari auth.users ke public.users
INSERT INTO public.users (id, email, full_name, created_at, updated_at)
SELECT 
  id::text, 
  email, 
  raw_user_meta_data->>'full_name' as full_name,
  created_at,
  updated_at
FROM auth.users
WHERE id::text NOT IN (SELECT id FROM public.users)
ON CONFLICT (id) DO NOTHING;

-- B. RLS policy agar user bisa buat/lihat profile sendiri
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'users' AND policyname = 'users_select_own'
  ) THEN
    CREATE POLICY users_select_own ON public.users
      FOR SELECT USING (auth.uid()::text = id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'users' AND policyname = 'users_insert_own'
  ) THEN
    CREATE POLICY users_insert_own ON public.users
      FOR INSERT WITH CHECK (auth.uid()::text = id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'users' AND policyname = 'users_update_own'
  ) THEN
    CREATE POLICY users_update_own ON public.users
      FOR UPDATE USING (auth.uid()::text = id) WITH CHECK (auth.uid()::text = id);
  END IF;
END $$;

-- C. Trigger untuk auto-create public.users saat auth.users dibuat
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.users (id, email, full_name, created_at, updated_at)
  VALUES (
    NEW.id::text,
    NEW.email,
    NEW.raw_user_meta_data->>'full_name',
    NEW.created_at,
    NEW.updated_at
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- B. Verify: Check jika ada messages/transactions dengan user_id invalid
SELECT 'Orphaned Messages' as issue, COUNT(*) as count
FROM public.messages 
WHERE user_id IS NOT NULL 
  AND user_id NOT IN (SELECT id FROM public.users)
UNION ALL
SELECT 'Orphaned Transactions', COUNT(*)
FROM public.transactions 
WHERE user_id IS NOT NULL 
  AND user_id NOT IN (SELECT id FROM public.users);

-- C. FIX orphaned data - Set NULL atau delete (pilih salah satu):

-- OPTION 1: Set user_id NULL untuk orphaned records (SAFE)
UPDATE public.messages 
SET user_id = NULL 
WHERE user_id IS NOT NULL 
  AND user_id NOT IN (SELECT id FROM public.users);

UPDATE public.transactions 
SET user_id = NULL 
WHERE user_id IS NOT NULL 
  AND user_id NOT IN (SELECT id FROM public.users);

-- OPTION 2: Delete orphaned records (DANGEROUS - data hilang!)
-- DELETE FROM public.messages 
-- WHERE user_id IS NOT NULL 
--   AND user_id NOT IN (SELECT id FROM public.users);

-- D. Fix orphaned group_id (jika ada)
UPDATE public.transactions 
SET group_id = NULL 
WHERE group_id IS NOT NULL 
  AND group_id NOT IN (SELECT id FROM public.groups);

UPDATE public.messages 
SET group_id = NULL 
WHERE group_id IS NOT NULL 
  AND group_id NOT IN (SELECT id FROM public.groups);


-- =========================================================
-- RLS: MESSAGES (GROUP CHAT ACCESS)
-- =========================================================

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'messages' AND policyname = 'messages_select_group_member'
  ) THEN
    CREATE POLICY messages_select_group_member ON public.messages
      FOR SELECT USING (
        (group_id IS NULL AND user_id = auth.uid()::text)
        OR (group_id IS NOT NULL AND group_id IN (
          SELECT group_id FROM public.group_members WHERE user_id = auth.uid()::text
        ))
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'messages' AND policyname = 'messages_insert_group_member'
  ) THEN
    CREATE POLICY messages_insert_group_member ON public.messages
      FOR INSERT WITH CHECK (
        (group_id IS NULL AND user_id = auth.uid()::text)
        OR (group_id IS NOT NULL AND group_id IN (
          SELECT group_id FROM public.group_members WHERE user_id = auth.uid()::text
        ))
      );
  END IF;
END $$;


-- =========================================================
-- DISABLE EMAIL VERIFICATION (REQUIRED) - LANGKAH DETAIL
-- =========================================================

-- CARA 1: Supabase Dashboard (PALING MUDAH)
-- Step-by-step dengan screenshot lokasi:
-- 
-- 1. Buka: https://supabase.com/dashboard/project/YOUR_PROJECT_ID
-- 2. Klik menu "Authentication" di sidebar KIRI
-- 3. Klik tab "Providers" di bagian ATAS
-- 4. Scroll cari bagian "Email" provider (biasanya paling atas)
-- 5. Klik "Email" untuk expand settings
-- 6. Cari toggle/checkbox:
--    - "Confirm email" ATAU
--    - "Enable email confirmations" ATAU  
--    - "Email confirmation required"
-- 7. MATIKAN toggle tersebut (OFF/Disabled)
-- 8. Klik tombol "Save" di kanan bawah
-- 9. RESTART app Flutter setelah save
--
-- LOKASI ALTERNATIF (jika tidak di Providers):
-- - Authentication > Settings > Email Auth
-- - Authentication > Email > Advanced Settings


-- CARA 2: SQL Direct
-- NOTE: Di beberapa project Supabase, tabel auth.config tidak tersedia.
-- Jika muncul error "relation auth.config does not exist", gunakan CARA 1 (Dashboard).

-- =========================================================
-- DELETE UNVERIFIED USERS (OPTIONAL)
-- =========================================================

-- Jika ada user yang sudah register tapi belum verified,
-- hapus mereka agar bisa register ulang:

-- DELETE FROM auth.users WHERE email_confirmed_at IS NULL;

-- ATAU hapus user tertentu saja:
-- DELETE FROM auth.users WHERE email = 'triankaputama@gmail.com' AND email_confirmed_at IS NULL;
