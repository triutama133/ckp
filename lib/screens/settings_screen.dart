import 'package:catatan_keuangan_pintar/screens/login_screen.dart';
import 'package:catatan_keuangan_pintar/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _voiceAutoSave = true;

  static const _prefVoiceAutoSave = 'voice_auto_save';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final name = AuthService.instance.userName ?? '';
    final email = AuthService.instance.userEmail ?? '';
    _nameCtrl.text = name;
    _emailCtrl.text = email;
    () async {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _voiceAutoSave = prefs.getBool(_prefVoiceAutoSave) ?? true;
        _loading = false;
      });
    }();
  }

  Future<void> _saveProfile() async {
    if (!AuthService.instance.isLoggedIn) return;
    setState(() => _saving = true);
    try {
      final newName = _nameCtrl.text.trim();
      final newEmail = _emailCtrl.text.trim();

      if (newName.isNotEmpty) {
        await AuthService.instance.updateProfile(fullName: newName);
      }
      if (newEmail.isNotEmpty && newEmail != AuthService.instance.userEmail) {
        await AuthService.instance.updateEmail(newEmail);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pengaturan akun berhasil disimpan')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan: $e')),
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _resetPassword() async {
    final email = AuthService.instance.userEmail;
    if (email == null || email.isEmpty) return;
    try {
      await AuthService.instance.resetPassword(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email reset password dikirim')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengirim reset: $e')),
        );
      }
    }
  }

  Future<void> _toggleVoiceAutoSave(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefVoiceAutoSave, value);
    setState(() => _voiceAutoSave = value);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    if (!AuthService.instance.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pengaturan Akun')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Mode Guest',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Login untuk mengubah nama atau email dan menyinkronkan data.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (route) => false,
                    );
                  },
                  icon: const Icon(Icons.login),
                  label: const Text('Login / Daftar'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan Akun')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Profil', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Nama Lengkap',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _saveProfile,
              icon: const Icon(Icons.save),
              label: Text(_saving ? 'Menyimpan...' : 'Simpan Perubahan'),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          const Text('Preferensi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-save Voice'),
            subtitle: const Text('Simpan otomatis jika tidak ada konfirmasi 5 detik'),
            value: _voiceAutoSave,
            onChanged: _toggleVoiceAutoSave,
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          const Text('Keamanan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.lock_reset),
            title: const Text('Reset Password'),
            subtitle: const Text('Kami akan kirim email reset password'),
            onTap: _resetPassword,
          ),
        ],
      ),
    );
  }
}
