import 'package:catatan_keuangan_pintar/services/sync_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SyncSettingsScreen extends StatefulWidget {
  const SyncSettingsScreen({Key? key}) : super(key: key);

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  String _strategy = 'last_write_wins';
  int _lastSync = 0;
  bool _loading = true;
  bool _syncing = false;
  bool _autoSync = true;
  int _intervalMinutes = 5;

  static const _prefLastSync = 'sync_last_at';
  static const _prefAutoSync = 'sync_auto_enabled';
  static const _prefInterval = 'sync_interval_min';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final strategy = await SyncService.instance.getStrategy();
    setState(() {
      _strategy = strategy;
      _lastSync = prefs.getInt(_prefLastSync) ?? 0;
      _autoSync = prefs.getBool(_prefAutoSync) ?? true;
      _intervalMinutes = prefs.getInt(_prefInterval) ?? 5;
      _loading = false;
    });
  }

  Future<void> _saveStrategy(String value) async {
    await SyncService.instance.setStrategy(value);
    setState(() => _strategy = value);
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    try {
      await SyncService.instance.syncAll();
      final prefs = await SharedPreferences.getInstance();
      setState(() => _lastSync = prefs.getInt(_prefLastSync) ?? 0);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sinkronisasi selesai')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sinkronisasi gagal: $e')),
        );
      }
    }
    if (mounted) setState(() => _syncing = false);
  }

  Future<void> _toggleAutoSync(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefAutoSync, value);
    setState(() => _autoSync = value);
    if (value) {
      SyncService.instance.startAutoSync(interval: Duration(minutes: _intervalMinutes));
    } else {
      SyncService.instance.stopAutoSync();
    }
  }

  Future<void> _setInterval(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefInterval, minutes);
    setState(() => _intervalMinutes = minutes);
    if (_autoSync) {
      SyncService.instance.startAutoSync(interval: Duration(minutes: minutes));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final lastSyncText = _lastSync == 0
        ? 'Belum pernah'
        : DateFormat('dd MMM yyyy HH:mm', 'id').format(DateTime.fromMillisecondsSinceEpoch(_lastSync));

    return Scaffold(
      appBar: AppBar(title: const Text('Sinkronisasi')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Status', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Terakhir sinkron: $lastSyncText'),
          const SizedBox(height: 16),
          const Text('Strategi Konflik', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _strategy,
            items: const [
              DropdownMenuItem(value: 'last_write_wins', child: Text('Prioritas terbaru')),
              DropdownMenuItem(value: 'local_wins', child: Text('Utamakan lokal')),
              DropdownMenuItem(value: 'remote_wins', child: Text('Utamakan cloud')),
            ],
            onChanged: (v) => _saveStrategy(v ?? _strategy),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _syncing ? null : _syncNow,
              icon: const Icon(Icons.sync),
              label: Text(_syncing ? 'Menyinkron...' : 'Sync Sekarang'),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          const Text('Auto Sync', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Aktifkan auto-sync'),
            value: _autoSync,
            onChanged: _toggleAutoSync,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _intervalMinutes,
            items: const [
              DropdownMenuItem(value: 5, child: Text('5 menit')),
              DropdownMenuItem(value: 15, child: Text('15 menit')),
              DropdownMenuItem(value: 30, child: Text('30 menit')),
              DropdownMenuItem(value: 60, child: Text('60 menit')),
            ],
            onChanged: (v) => _setInterval(v ?? _intervalMinutes),
            decoration: const InputDecoration(labelText: 'Interval auto-sync'),
          ),
        ],
      ),
    );
  }
}
