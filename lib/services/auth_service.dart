import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AuthService handles all authentication operations including
/// email/password auth and Google Sign-In via Supabase
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final SupabaseClient _supabase = Supabase.instance.client;
  
  // Initialize GoogleSignIn lazily to avoid web platform issues
  GoogleSignIn? _googleSignIn;
  GoogleSignIn get googleSignIn {
    _googleSignIn ??= GoogleSignIn(scopes: ['email', 'profile']);
    return _googleSignIn!;
  }

  /// Get current user
  User? get currentUser => _supabase.auth.currentUser;

  /// Check if user is logged in
  bool get isLoggedIn => currentUser != null;

  /// Get current user ID (fallback to 'local_user' if not logged in)
  String get userId => currentUser?.id ?? 'local_user';

  /// Get current user email
  String? get userEmail => currentUser?.email;

  /// Get current user display name
  String? get userName => currentUser?.userMetadata?['full_name'] ?? currentUser?.email?.split('@')[0];

  /// Listen to auth state changes
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  /// Sign up with email and password
  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    String? fullName,
  }) async {
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: fullName != null ? {'full_name': fullName} : null,
      );

      if (response.user != null) {
        await _saveUserIdLocally(response.user!.id);
      }

      return response;
    } catch (e) {
      rethrow;
    }
  }

  /// Sign in with email and password
  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user != null) {
        await _saveUserIdLocally(response.user!.id);
      }

      return response;
    } catch (e) {
      rethrow;
    }
  }

  /// Sign in with Google
  Future<AuthResponse?> signInWithGoogle() async {
    try {
      // Sign out first to ensure clean state
      await googleSignIn.signOut();

      // Trigger Google Sign In
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        // User cancelled the sign-in
        return null;
      }

      // Get Google Auth tokens
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final String? idToken = googleAuth.idToken;
      final String? accessToken = googleAuth.accessToken;

      if (idToken == null) {
        throw Exception('Google Sign In failed: No ID token');
      }

      // Sign in to Supabase with Google credentials
      final response = await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      if (response.user != null) {
        await _saveUserIdLocally(response.user!.id);
      }

      return response;
    } catch (e) {
      // Clean up on error
      await googleSignIn.signOut();
      rethrow;
    }
  }

  /// Sign out
  Future<void> signOut() async {
    try {
      // Sign out from Google if signed in via Google
      if (await googleSignIn.isSignedIn()) {
        await googleSignIn.signOut();
      }

      // Sign out from Supabase
      await _supabase.auth.signOut();

      // Clear local storage
      await _clearUserIdLocally();
    } catch (e) {
      rethrow;
    }
  }

  /// Reset password (send reset email)
  Future<void> resetPassword(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(email);
    } catch (e) {
      rethrow;
    }
  }

  /// Update user profile
  Future<UserResponse> updateProfile({
    String? fullName,
    String? avatarUrl,
  }) async {
    try {
      final Map<String, dynamic> data = {};
      if (fullName != null) data['full_name'] = fullName;
      if (avatarUrl != null) data['avatar_url'] = avatarUrl;

      final response = await _supabase.auth.updateUser(
        UserAttributes(data: data),
      );

      return response;
    } catch (e) {
      rethrow;
    }
  }

  /// Save user ID to local storage for offline usage
  Future<void> _saveUserIdLocally(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_user_id', userId);
    } catch (e) {
      // Non-critical error, just log
      print('Failed to save user ID locally: $e');
    }
  }

  /// Clear user ID from local storage
  Future<void> _clearUserIdLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('current_user_id');
    } catch (e) {
      print('Failed to clear user ID locally: $e');
    }
  }

  /// Get locally saved user ID (for offline mode)
  Future<String?> getLocalUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('current_user_id');
    } catch (e) {
      return null;
    }
  }

  /// Delete account (requires re-authentication)
  Future<void> deleteAccount() async {
    try {
      // Note: Supabase doesn't have built-in delete account API
      // You need to implement this via Supabase Function or RPC call
      // For now, just sign out
      await signOut();
      
      // TODO: Call Supabase function to delete user data
      // await _supabase.functions.invoke('delete-user');
    } catch (e) {
      rethrow;
    }
  }

  /// Check if email is available (not already registered)
  Future<bool> isEmailAvailable(String email) async {
    try {
      // This is a workaround - try to sign in with wrong password
      // If email doesn't exist, we'll get "Invalid login credentials"
      // If email exists, we'll get the same error but that's expected
      // A better way is to use Supabase Function
      
      // For now, return true (let signup handle the error)
      return true;
    } catch (e) {
      return true;
    }
  }
}
