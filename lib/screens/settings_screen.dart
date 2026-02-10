import 'package:catatan_keuangan_pintar/screens/login_screen.dart';
import 'package:catatan_keuangan_pintar/services/auth_service.dart';
import 'package:catatan_keuangan_pintar/services/tutorial_service.dart';
import 'package:catatan_keuangan_pintar/widgets/hint_widgets.dart';
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

  void _showAppGuide(BuildContext context) {
    FeatureGuideSheet.show(
      context: context,
      title: 'Panduan Aplikasi',
      steps: [
        const GuideStep(
          title: 'Dashboard',
          description: 'Lihat ringkasan keuangan Anda: pemasukan, pengeluaran, saldo, dan grafik analisis.',
          icon: Icons.dashboard,
        ),
        const GuideStep(
          title: 'Chat Input',
          description: 'Input transaksi dengan bahasa natural, contoh: "beli nasi goreng 25rb" atau "gaji bulan ini 5 juta".',
          icon: Icons.chat,
        ),
        const GuideStep(
          title: 'Input Manual',
          description: 'Gunakan form lengkap untuk memasukkan transaksi dengan detail kategori, akun, dan target.',
          icon: Icons.edit,
        ),
        const GuideStep(
          title: 'Target & Goals',
          description: 'Buat dan kelola target tabungan seperti Haji, Umroh, Rumah, atau investasi lainnya.',
          icon: Icons.flag,
        ),
        const GuideStep(
          title: 'Akun & Sumber Dana',
          description: 'Kelola berbagai akun: Bank, Tunai, Dompet Digital, Kartu Kredit. Track saldo setiap akun.',
          icon: Icons.account_balance_wallet,
        ),
        const GuideStep(
          title: 'Kategori',
          description: 'Atur kategori pemasukan dan pengeluaran. Bisa dibuat otomatis atau custom sesuai kebutuhan.',
          icon: Icons.category,
        ),
        const GuideStep(
          title: 'Scan Struk',
          description: 'Gunakan kamera untuk scan struk belanja. Aplikasi akan ekstrak informasi secara otomatis.',
          icon: Icons.camera_alt,
        ),
        const GuideStep(
          title: 'Voice Input',
          description: 'Gunakan suara untuk input transaksi dengan cepat, tanpa perlu mengetik.',
          icon: Icons.mic,
        ),
        const GuideStep(
          title: 'Notifikasi & Insights',
          description: 'Dapatkan analisis pola pengeluaran, tips menabung, dan reminder untuk goal Anda.',
          icon: Icons.notifications,
        ),
        const GuideStep(
          title: 'Kolaborasi Grup',
          description: 'Buat grup keuangan keluarga atau tim untuk berbagi transaksi dan target bersama.',
          icon: Icons.group,
        ),
      ],
    );
  }

  Future<void> _resetTutorials() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Tutorial'),
        content: const Text('Apakah Anda yakin ingin menampilkan kembali semua tutorial?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await TutorialService.instance.resetAllTutorials();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tutorial berhasil direset. Buka fitur untuk melihat tutorial kembali.')),
        );
      }
    }
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
          const Text('Bantuan & Tutorial', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.help_outline, color: Colors.blue),
            title: const Text('Panduan Aplikasi'),
            subtitle: const Text('Lihat panduan lengkap fitur aplikasi'),
            onTap: () => _showAppGuide(context),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.refresh, color: Colors.orange),
            title: const Text('Reset Tutorial'),
            subtitle: const Text('Tampilkan kembali tutorial untuk pengguna baru'),
            onTap: () => _resetTutorials(),
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
