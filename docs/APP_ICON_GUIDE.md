# Panduan Mengganti Icon Aplikasi

Aplikasi ini menggunakan icon wallet (dompet) yang sesuai dengan tampilan splash screen.

## Langkah-langkah:

### 1. Siapkan Gambar Icon
Buat atau dapatkan gambar icon dengan spesifikasi:
- Format: PNG dengan background transparan
- Ukuran: 1024x1024 px (minimal 512x512 px)
- Desain: Icon wallet/dompet yang sesuai dengan tema aplikasi
- Warna: Sebaiknya menggunakan warna primary aplikasi (biru #2196F3)

**Rekomendasi**: Gunakan icon wallet yang mirip dengan `Icons.account_balance_wallet_rounded` dari Material Icons, atau buat desain custom dengan tema wallet/dompet.

### 2. Simpan Gambar
- Buat folder: `assets/icon/`
- Simpan gambar icon sebagai: `assets/icon/app_icon.png`
- Untuk adaptive icon Android, buat juga: `assets/icon/app_icon_foreground.png` (hanya icon tanpa background)

### 3. Update pubspec.yaml
Sudah dilakukan! File `pubspec.yaml` sudah di-update dengan package `flutter_launcher_icons`.

### 4. Konfigurasi Icon
Sudah dilakukan! File `flutter_launcher_icons.yaml` sudah dibuat dengan konfigurasi untuk semua platform.

### 5. Generate Icons
Jalankan perintah berikut di terminal:

```bash
# Install dependencies
flutter pub get

# Generate launcher icons untuk semua platform
flutter pub run flutter_launcher_icons
```

Perintah ini akan otomatis membuat icon untuk:
- Android (semua densitas: mdpi, hdpi, xhdpi, xxhdpi, xxxhdpi)
- iOS (semua ukuran yang dibutuhkan)
- Web
- Windows
- macOS
- Linux

### 6. Verifikasi
- Build aplikasi dan periksa icon di perangkat/emulator
- Untuk Android: `flutter run` atau build APK
- Untuk iOS: Build melalui Xcode

## Alternatif: Menggunakan Icon Online Generator

Jika tidak memiliki gambar icon siap pakai, gunakan salah satu tool online:

1. **Figma** atau **Adobe Illustrator**: Buat desain icon wallet custom
2. **Flaticon.com**: Download icon wallet gratis (perhatikan lisensi)
3. **Icons8**: Icon wallet dengan berbagai style
4. **Canva**: Buat icon sederhana dengan template

## Catatan Penting:
- Icon harus square (1:1 aspect ratio)
- Gunakan PNG dengan transparency untuk hasil terbaik
- Adaptive icon Android memerlukan foreground layer terpisah
- Icon akan di-resize otomatis untuk berbagai ukuran platform

## Referensi:
- Flutter Launcher Icons: https://pub.dev/packages/flutter_launcher_icons
- Material Design Icons: https://fonts.google.com/icons
