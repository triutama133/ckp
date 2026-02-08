# 🚀 Setup Supabase untuk Authentication

## Kenapa Supabase?
- ✅ **GRATIS** - Free tier sangat generous untuk startup
- ✅ **Database PostgreSQL** - Robust dan powerful
- ✅ **Authentication built-in** - Email/password sudah include
- ✅ **Real-time** - Support real-time subscriptions
- ✅ **Storage** - File upload gratis 1GB
- ✅ **No backend code needed** - Langsung pakai dari Flutter

---

## 📋 Step 1: Buat Akun Supabase

1. Buka [supabase.com](https://supabase.com/)
2. Klik **"Start your project"**
3. Sign up dengan GitHub (gratis)
4. Klik **"New Project"**

### Isi Project Details:
```
Name: ckp-temp
Database Password: [buat password kuat, simpan baik-baik]
Region: Southeast Asia (Singapore) - paling dekat Indonesia
Pricing Plan: Free ($0/month)
```

5. Klik **"Create new project"**
6. Tunggu ~2 menit sampai project siap

---

## 📋 Step 2: Setup Authentication

1. Di Supabase Dashboard, pilih project Anda
2. Klik **"Authentication"** di sidebar kiri
3. Klik **"Providers"**

### Enable Email Provider:
- **Email** - Sudah enabled by default ✅
- **Confirm email** - Toggle OFF (untuk testing) atau ON (untuk production)
- Klik **"Save"**

### (Optional) Customize Email Templates:
1. Klik **"Email Templates"**
2. Edit template untuk:
   - **Confirm signup** - Email verifikasi pendaftaran
   - **Reset password** - Email reset password
   - **Magic link** - Passwordless login

---

## 📋 Step 3: Dapatkan API Keys

1. Di Supabase Dashboard, klik **"Settings"** (gear icon)
2. Klik **"API"**

Anda akan lihat:
```
Project URL: https://xxxxxxxxxxx.supabase.co
anon public: eyJhbGc...
```

### Copy kedua values tersebut!

---

## 📋 Step 4: Update Flutter App

### Cara 1: Update di Code (Simple)

Edit file `lib/services/supabase_init.dart`:

```dart
Future<void> initSupabase({String? url, String? anonKey}) async {
  final _url = url ?? 'https://xxxxxxxxxxx.supabase.co'; // ← Paste URL Anda
  final _anon = anonKey ?? 'eyJhbGc...'; // ← Paste anon key Anda

  await Supabase.initialize(
    url: _url,
    anonKey: _anon,
  );
}
```

### Cara 2: Environment Variables (Recommended untuk Production)

1. Buat file `.env` di root project:
```env
SUPABASE_URL=https://xxxxxxxxxxx.supabase.co
SUPABASE_ANON_KEY=eyJhbGc...
```

2. Tambahkan ke `.gitignore`:
```
.env
```

3. Run app dengan:
```bash
flutter run --dart-define=SUPABASE_URL=$SUPABASE_URL \
            --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY
```

---

## 📋 Step 5: (Optional) Buat Tabel Database

Untuk menyimpan data transaksi, buat tabel di Supabase:

1. Klik **"SQL Editor"** di sidebar
2. Click **"New query"**
3. Paste SQL berikut:

```sql
-- Tabel untuk menyimpan transaksi user
CREATE TABLE transactions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  amount DECIMAL(15, 2) NOT NULL,
  category TEXT,
  type TEXT NOT NULL, -- 'income' atau 'expense'
  date TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  description TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index untuk query cepat
CREATE INDEX idx_transactions_user_id ON transactions(user_id);
CREATE INDEX idx_transactions_date ON transactions(date);

-- Row Level Security (RLS) - User hanya bisa lihat data sendiri
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;

-- Policy: User bisa baca data sendiri
CREATE POLICY "Users can read own transactions"
  ON transactions FOR SELECT
  USING (auth.uid() = user_id);

-- Policy: User bisa insert data sendiri
CREATE POLICY "Users can insert own transactions"
  ON transactions FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Policy: User bisa update data sendiri
CREATE POLICY "Users can update own transactions"
  ON transactions FOR UPDATE
  USING (auth.uid() = user_id);

-- Policy: User bisa delete data sendiri
CREATE POLICY "Users can delete own transactions"
  ON transactions FOR DELETE
  USING (auth.uid() = user_id);
```

4. Klik **"Run"** (atau Ctrl+Enter)

---

## 🧪 Step 6: Test Authentication

### Test Register:
1. Run app: `flutter run`
2. Klik **"Daftar"**
3. Isi:
   - Nama: Test User
   - Email: test@example.com
   - Password: test123
   - Konfirmasi Password: test123
   - ✅ Setuju dengan S&K
4. Klik **"Daftar"**

### Cek di Supabase:
1. Buka Supabase Dashboard
2. Klik **"Authentication"** → **"Users"**
3. Anda akan lihat user baru! ✅

### Test Login:
1. Logout dari app
2. Login dengan:
   - Email: test@example.com
   - Password: test123
3. Berhasil! 🎉

---

## 🔒 Security Best Practices

### 1. **Row Level Security (RLS)**
Pastikan RLS enabled untuk semua tabel:
```sql
ALTER TABLE your_table ENABLE ROW LEVEL SECURITY;
```

### 2. **Email Verification**
Enable di production:
- Supabase Dashboard → Authentication → Providers
- Email → Confirm email: **ON**

### 3. **Password Policy**
Set minimum password strength:
- Authentication → Configuration
- Minimum password length: 8
- Require: Uppercase, Number, Symbol

### 4. **Rate Limiting**
Supabase otomatis rate limit:
- Max 60 requests/minute per IP
- Protection dari brute force

### 5. **HTTPS Only**
Supabase otomatis enforce HTTPS ✅

---

## 💰 Supabase Free Tier Limits

```
✅ Database: 500 MB
✅ Auth Users: Unlimited!
✅ Storage: 1 GB
✅ Bandwidth: 2 GB/month
✅ API Requests: Unlimited
✅ Edge Functions: 500K invocations/month
```

**Cukup banget untuk startup!** 🚀

Jika exceed:
- Auto-pause (tidak auto-charge)
- Upgrade ke Pro: $25/month

---

## 🐛 Troubleshooting

### Error: "Invalid API key"
- ✅ Cek URL dan anon key sudah benar
- ✅ Pastikan tidak ada space/newline
- ✅ Restart app setelah update

### Error: "Email not confirmed"
- ✅ Cek email untuk confirmation link
- ✅ Atau disable "Confirm email" untuk testing

### Error: "Network error"
- ✅ Cek internet connection
- ✅ Cek Supabase project masih aktif (buka dashboard)
- ✅ Cek firewall tidak block Supabase

### Database Query Error
- ✅ Cek RLS policies sudah benar
- ✅ Test query di SQL Editor dulu
- ✅ Cek user sudah login sebelum query

---

## 📚 Next Steps

Setelah authentication jalan:

1. **Buat tabel database** untuk transaksi (lihat Step 5)
2. **Implement CRUD** untuk transaksi:
   ```dart
   // Insert transaction
   await supabase.from('transactions').insert({
     'user_id': userId,
     'title': 'Beli kopi',
     'amount': -25000,
     'category': 'Food & Drink',
     'type': 'expense',
   });
   
   // Get transactions
   final data = await supabase
     .from('transactions')
     .select()
     .eq('user_id', userId)
     .order('date', ascending: false);
   ```

3. **Real-time sync** untuk multi-device:
   ```dart
   supabase
     .from('transactions')
     .stream(primaryKey: ['id'])
     .eq('user_id', userId)
     .listen((data) {
       // Update UI when data changes
     });
   ```

4. **Profile management** - Edit nama, avatar, dll
5. **Storage** - Upload profile picture, receipts

---

## 🆚 Alternatif: Self-Hosted / VPS

Jika ingin host sendiri di VPS:

### Option 1: Self-hosted Supabase
```bash
git clone https://github.com/supabase/supabase
cd supabase/docker
docker compose up -d
```

Butuh:
- VPS minimal 2GB RAM
- Docker + Docker Compose
- Domain + SSL certificate

### Option 2: PostgreSQL + Custom Backend
- Install PostgreSQL
- Buat REST API (Node.js/Python/Go)
- Handle auth sendiri (JWT tokens)

**Tapi lebih ribet dan mahal!** VPS murah ~$5/month, tapi:
- Harus maintain server
- Setup security sendiri
- No built-in auth/storage
- Scaling susah

**Rekomendasi: Pakai Supabase free tier dulu!** 🎯

---

## ✅ Checklist

- [ ] Buat akun Supabase
- [ ] Create new project
- [ ] Enable email authentication
- [ ] Copy Project URL dan anon key
- [ ] Update `supabase_init.dart`
- [ ] Test register user baru
- [ ] Test login user
- [ ] Test logout
- [ ] (Optional) Buat tabel transactions
- [ ] (Optional) Enable email verification

---

**Selamat! Authentication Anda sudah jalan! 🎉**

Jika ada masalah, cek:
1. Supabase Dashboard → Logs
2. Flutter debug console
3. Supabase Status: https://status.supabase.com/
