# Setup Google Sign-In

## Prerequisites
1. Google Cloud Project
2. Supabase Project

## Google Cloud Console Setup

### 1. Create OAuth 2.0 Credentials

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Select your project or create a new one
3. Navigate to **APIs & Services > Credentials**
4. Click **Create Credentials > OAuth 2.0 Client IDs**

### 2. Configure OAuth Consent Screen

1. Go to **APIs & Services > OAuth consent screen**
2. Choose **External** user type
3. Fill in app information:
   - App name: **Catatan Keuangan Pintar**
   - User support email: Your email
   - Developer contact email: Your email
4. Add scopes: `email`, `profile`
5. Save and continue

### 3. Create OAuth Client IDs

#### For Android:
1. Create **Android** client ID
2. Package name: `com.example.catatan_keuangan_pintar`
3. Get SHA-1 certificate:
   ```bash
   # For debug:
   keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
   
   # For release:
   keytool -list -v -keystore /path/to/your/keystore -alias your_alias
   ```
4. Enter the SHA-1 fingerprint
5. Save the Client ID

#### For iOS:
1. Create **iOS** client ID
2. Bundle ID: `com.example.catatanKeuanganPintar`
3. Save the Client ID

#### For Web:
1. Create **Web application** client ID
2. Add authorized redirect URIs:
   ```
   https://YOUR_SUPABASE_PROJECT_URL/auth/v1/callback
   ```
3. Save the Client ID

## Supabase Configuration

### 1. Enable Google Provider

1. Go to your Supabase project dashboard
2. Navigate to **Authentication > Providers**
3. Find **Google** in the list
4. Click **Enable**
5. Enter your Google OAuth credentials:
   - **Client ID**: Your Google Web Client ID
   - **Client Secret**: Your Google Web Client Secret
6. Add authorized redirect URL (auto-filled)
7. Save

### 2. Get Supabase Credentials

From your Supabase project dashboard:
- **Project URL**: `https://xxx.supabase.co`
- **Anon Public Key**: Found in Settings > API

## App Configuration

### 1. Update Supabase Initialization

File: `lib/services/supabase_init.dart`

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> initSupabase() async {
  await Supabase.initialize(
    url: 'YOUR_SUPABASE_PROJECT_URL',
    anonKey: 'YOUR_SUPABASE_ANON_KEY',
  );
}
```

### 2. Android Configuration

File: `android/app/build.gradle`

Add defaultConfig:
```gradle
android {
    ...
    defaultConfig {
        ...
        minSdkVersion 21
        targetSdkVersion 34
    }
}
```

### 3. iOS Configuration

File: `ios/Runner/Info.plist`

Add URL scheme:
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.googleusercontent.apps.YOUR_IOS_CLIENT_ID</string>
        </array>
    </dict>
</array>
```

### 4. Google Logo Asset (Optional)

Download Google logo and place it at:
```
assets/google_logo.png
```

Update `pubspec.yaml`:
```yaml
flutter:
  assets:
    - assets/google_logo.png
    - assets/fasttext/
```

## Testing

### Test Login Flow:
1. Run the app: `flutter run`
2. Click "Login dengan Google"
3. Select Google account
4. Grant permissions
5. Should redirect to HomeScreen

### Test Logout:
1. Go to "More" tab
2. Click "Logout"
3. Confirm logout
4. Should redirect to LoginScreen

### Test Guest Mode:
1. On LoginScreen, click "Lanjut tanpa login (Mode Guest)"
2. Should go to HomeScreen without authentication
3. User info section shows "Mode Guest" with login prompt

## Troubleshooting

### "Google Sign-In failed"
- Check your Google OAuth Client IDs
- Verify SHA-1 fingerprints (Android)
- Check bundle ID matches (iOS)
- Ensure Supabase Google provider is enabled

### "Network Error"
- Check internet connection
- Verify Supabase URL and API key
- Check if Supabase project is active

### "User already registered"
- Email is already taken
- Try login instead of register
- Or use a different email

## Security Notes

⚠️ **Important:**
- Never commit Supabase keys to public repositories
- Use environment variables for sensitive data
- Enable Row Level Security (RLS) in Supabase
- Implement email verification for production

## Production Checklist

- [ ] Generate production SHA-1 certificate
- [ ] Update OAuth consent screen to production
- [ ] Enable email verification in Supabase
- [ ] Set up proper error logging
- [ ] Implement biometric authentication (optional)
- [ ] Add password reset flow
- [ ] Implement account deletion
- [ ] Set up proper RLS policies in Supabase
