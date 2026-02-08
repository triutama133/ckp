import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:catatan_keuangan_pintar/services/group_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _useRemote = false;
  String _provider = 'vps';
  final _vpsController = TextEditingController();
  bool _loading = true;

  static const _keyUseRemote = 'group_use_remote';
  static const _keyProvider = 'group_provider';
  static const _keyRemoteBase = 'group_remote_base';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _useRemote = prefs.getBool(_keyUseRemote) ?? GroupService.instance.useRemote;
      _provider = prefs.getString(_keyProvider) ?? GroupService.instance.provider;
      _vpsController.text = prefs.getString(_keyRemoteBase) ?? (GroupService.instance.remoteBaseUrl ?? '');
      _loading = false;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyUseRemote, _useRemote);
    await prefs.setString(_keyProvider, _provider);
    await prefs.setString(_keyRemoteBase, _vpsController.text.trim());

    GroupService.instance.useRemote = _useRemote;
    GroupService.instance.provider = _provider;
    GroupService.instance.remoteBaseUrl = _vpsController.text.trim().isEmpty ? null : _vpsController.text.trim();

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pengaturan tersimpan')));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SwitchListTile(
          title: const Text('Gunakan layanan remote (Supabase / VPS)'),
          value: _useRemote,
          onChanged: (v) => setState(() => _useRemote = v),
        ),
        const SizedBox(height: 8),
        Text('Pilih provider remote', style: Theme.of(context).textTheme.titleMedium),
        RadioListTile<String>(title: const Text('VPS (self-host)'), value: 'vps', groupValue: _provider, onChanged: (v) => setState(() => _provider = v!)),
        RadioListTile<String>(title: const Text('Supabase'), value: 'supabase', groupValue: _provider, onChanged: (v) => setState(() => _provider = v!)),
        const SizedBox(height: 12),
        TextField(controller: _vpsController, decoration: const InputDecoration(labelText: 'VPS Base URL (https://...)', hintText: 'https://api.example.com')),
        const SizedBox(height: 16),
        ElevatedButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Simpan')),
        const SizedBox(height: 12),
        Text('Catatan:', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        const Text('Jika memilih Supabase, inisialisasi Supabase di app.dart dengan URL dan anon key sebelum menggunakan fitur remote.'),
      ]),
    );
  }
}
