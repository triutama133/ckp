# Catatan Keuangan Pintar - Aplikasi Keuangan Cerdas 💰

Aplikasi manajemen keuangan pribadi dengan AI dan fitur kolaborasi yang canggih.

## ✨ Fitur Utama

### 1. **Dashboard Keuangan yang Insightful** 📊
- Statistik real-time (Pemasukan, Pengeluaran, Saldo, Total Aset)
- Pie chart untuk analisis pengeluaran per kategori
- Progress bar untuk tracking goal/target
- Filter periode: Minggu, Bulan, Tahun
- Pull-to-refresh untuk update data

### 2. **Chat Interface Intuitif** 💬
- Input transaksi dengan bahasa natural
  - Contoh: "beli nasi goreng 25rb"
  - Contoh: "gaji bulan ini 5 juta"
  - Contoh: "tabung haji 500 ribu"
- Auto-parsing dengan FastText AI
- Riwayat percakapan tersimpan
- Support untuk voice input (coming soon in chat integration)
- Support untuk scan struk (coming soon in chat integration)

### 3. **Manual Transaction Entry** ✍️
- Form lengkap untuk input manual
- Pilih tipe: Pemasukan, Pengeluaran, Tabungan, Investasi
- Pilih kategori yang sesuai
- Pilih sumber dana (akun)
- Link ke target/goal (untuk tabungan/investasi)
- Tambah keterangan dan pilih tanggal

### 4. **Manajemen Target/Goals** 🎯
- Buat target tabungan (Haji, Umroh, Rumah, Mobil, dll)
- Track progress dengan progress bar visual
- Set target jumlah dan target tanggal
- Customize icon dan warna
- Setor langsung ke target
- Notifikasi otomatis saat target tercapai

### 5. **Akun & Sumber Dana** 🏦
- Kelola multiple akun:
  - Bank (BCA, Mandiri, BRI, dll)
  - Tunai/Kas
  - Dompet Digital (GoPay, OVO, DANA, dll)
  - Kartu Kredit
- Track saldo real-time setiap akun
- Customize icon dan warna untuk setiap akun
- Adjust balance dengan mudah
- Tampilan total saldo semua akun

### 6. **Kategori Custom** 🏷️
- 45+ kategori built-in
- Tambah kategori custom
- Keyword-based auto-kategorisasi
- Filter by type: income, expense, saving, investment

### 7. **OCR - Scan Struk Belanja** 📸
- Scan struk dari kamera atau galeri
- Auto-extract:
  - Nama merchant/toko
  - Tanggal transaksi
  - Total amount
  - Detail items (jika tersedia)
- Parse dengan Google ML Kit
- Preview hasil sebelum save

### 8. **Voice Input** 🎤
- Speech-to-text untuk input transaksi
- Support bahasa Indonesia
- Hands-free transaction entry
- Real-time transcription

### 9. **Smart Notifications & Insights** 🔔
- Analisis pengeluaran vs pemasukan
- Reminder untuk goal yang mendekati deadline
- Tips menabung cerdas
- Analisis pola pengeluaran:
  - High Spender
  - Saver
  - Balanced
  - Moderate Spender
- Rekomendasi dana darurat
- Daily insights

### 10. **Kolaborasi Grup (Coming Soon)** 👥
- Join grup keuangan keluarga/tim
- Shared transactions
- Real-time sync via Supabase
- Role-based permissions

## 🗂️ Struktur Database

### Tables:
1. **messages** - Riwayat chat
2. **transactions** - Semua transaksi dengan field:
   - accountId (link ke akun)
   - goalId (link ke target)
   - imageUrl (foto struk)
   - voiceUrl (voice note)
3. **categories** - Kategori custom + built-in
4. **accounts** - Sumber dana/akun
5. **goals** - Target tabungan
6. **groups** - Grup kolaborasi (untuk fitur grup chat)

## 🚀 Cara Install & Run

### 1. Install Dependencies
```bash
flutter pub get
```

### 2. Platform-Specific Setup

#### Android
Tidak ada setup tambahan yang diperlukan.

#### iOS
1. Buka `ios/Podfile` dan pastikan platform minimal iOS 12:
   ```ruby
   platform :ios, '12.0'
   ```

2. Install pods:
   ```bash
   cd ios
   pod install
   cd ..
   ```

3. Tambahkan permissions di `ios/Runner/Info.plist`:
   ```xml
   <key>NSCameraUsageDescription</key>
   <string>Aplikasi memerlukan akses kamera untuk scan struk</string>
   <key>NSPhotoLibraryUsageDescription</key>
   <string>Aplikasi memerlukan akses galeri untuk memilih foto struk</string>
   <key>NSMicrophoneUsageDescription</key>
   <string>Aplikasi memerlukan akses mikrofon untuk voice input</string>
   <key>NSSpeechRecognitionUsageDescription</key>
   <string>Aplikasi memerlukan akses speech recognition untuk voice input</string>
   ```

### 3. Run Application
```bash
flutter run
```

## 📱 Navigasi Aplikasi

### Bottom Navigation:
1. **Dashboard** - Overview keuangan
2. **Chat** - Input transaksi dengan chat
3. **Manual** - Input transaksi manual
4. **Lainnya** - Menu tambahan:
   - Target & Goals
   - Akun & Sumber Dana
   - Kategori
   - Notifikasi
   - Pengaturan

## 🎨 Design Highlights

- **Material Design 3** dengan color scheme yang konsisten
- **Gradient backgrounds** untuk visual yang menarik
- **Card-based UI** untuk grouping informasi
- **Icon & Emoji** untuk personalisasi
- **Progress indicators** yang interaktif
- **Smooth animations** dengan transitions
- **Pull-to-refresh** di semua list
- **Empty states** yang informatif

## 🔧 Services & Architecture

### Services:
- `DBService` - SQLite database operations
- `ParserService` - Natural language parsing
- `FastTextService` - ML-based categorization
- `OCRService` - Receipt scanning dengan ML Kit
- `VoiceService` - Speech-to-text
- `SmartNotificationService` - Insights & notifications

### State Management:
- Flutter Hooks untuk reactive state
- Provider (ready untuk complex state)

## 📊 Analytics & Insights

Aplikasi secara otomatis menganalisis:
1. **Spending Rate** - Persentase pengeluaran vs pemasukan
2. **Saving Rate** - Persentase tabungan vs pemasukan
3. **Goal Progress** - Tracking progress untuk setiap target
4. **Emergency Fund** - Rekomendasi dana darurat (6x pemasukan)
5. **Spending Pattern** - Pola pengeluaran user
6. **Top Categories** - Kategori pengeluaran terbanyak

## 🔐 Privacy & Security

- Data tersimpan lokal di SQLite (privacy first)
- Tidak ada tracking pihak ketiga
- Optional cloud sync via Supabase (untuk fitur grup)
- No ads, no data selling

## 🎯 Roadmap

- [x] Database schema lengkap
- [x] Dashboard dengan charts
- [x] Goals management
- [x] Account management
- [x] Manual transaction entry
- [x] OCR service
- [x] Voice input service
- [x] Smart notifications & insights
- [ ] Integrate OCR & Voice ke Chat screen
- [ ] Group collaboration via Supabase
- [ ] Export to Excel/PDF
- [ ] Budget planning
- [ ] Recurring transactions
- [ ] Multi-currency support
- [ ] Dark mode
- [ ] Backup & restore
- [ ] Cloud sync

## 📝 Tips Penggunaan

1. **Mulai dengan Setup Akun**: Tambahkan semua sumber dana Anda (bank, cash, e-wallet)
2. **Buat Target**: Set goals untuk motivasi menabung
3. **Gunakan Chat untuk Quick Entry**: Lebih cepat daripada manual
4. **Scan Struk**: Otomatis untuk belanja besar
5. **Review Dashboard**: Cek statistik secara rutin
6. **Perhatikan Insights**: Ikuti saran untuk keuangan lebih sehat

## 🤝 Contributing

Aplikasi ini masih dalam pengembangan aktif. Feedback dan suggestions sangat diterima!

## 📄 License

Private project - All rights reserved

---

**Dibuat dengan ❤️ menggunakan Flutter**
