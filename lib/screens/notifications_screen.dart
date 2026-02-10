import 'dart:convert';

import 'package:catatan_keuangan_pintar/services/notification_service.dart';
import 'package:catatan_keuangan_pintar/services/auth_service.dart';
import 'package:catatan_keuangan_pintar/services/group_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _dailyInsights = false;
  bool _loading = true;
  List<Map<String, dynamic>> _realtimeNotifs = [];
  RealtimeChannel? _channel;

  static const _keyDailyInsights = 'notify_daily_insights';

  Map<String, dynamic> _readData(dynamic raw) {
    if (raw is Map) {
      return Map<String, dynamic>.from(raw as Map);
    }
    if (raw is String && raw.isNotEmpty) {
      try {
        return Map<String, dynamic>.from(jsonDecode(raw));
      } catch (_) {}
    }
    return {};
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _dailyInsights = prefs.getBool(_keyDailyInsights) ?? false;
    });
    await _loadRealtimeNotifs();
    _subscribeRealtime();
    setState(() => _loading = false);
  }

  Future<void> _loadRealtimeNotifs() async {
    try {
      final uid = AuthService.instance.userId;
      final rows = await Supabase.instance.client
          .from('notifications')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(50);
      if (rows is List) {
        setState(() {
          _realtimeNotifs = rows.map((e) => Map<String, dynamic>.from(e)).toList();
        });
      }
    } catch (_) {}
  }

  void _subscribeRealtime() {
    final uid = AuthService.instance.userId;
    _channel?.unsubscribe();
    _channel = Supabase.instance.client.channel('notifs:$uid');
    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'notifications',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
      callback: (payload) {
        final data = payload.newRecord;
        if (data.isEmpty) return;
        setState(() {
          _realtimeNotifs = [Map<String, dynamic>.from(data), ..._realtimeNotifs];
        });
      },
    );
    _channel!.subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _toggleDailyInsights(bool value) async {
    setState(() => _dailyInsights = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDailyInsights, value);
    if (value) {
      await SmartNotificationService.instance.scheduleDailyInsights();
      await SmartNotificationService.instance.showDailyInsight();
    } else {
      await SmartNotificationService.instance.cancelDailyInsights();
    }
  }

  Future<void> _sendTest() async {
    await SmartNotificationService.instance.showNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: 'Notifikasi Aktif',
      body: 'Pengingat & saran pintar sudah siap.',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifikasi'),
        actions: [
          IconButton(
            tooltip: 'Tandai semua dibaca',
            icon: const Icon(Icons.done_all),
            onPressed: () async {
              try {
                final uid = AuthService.instance.userId;
                await Supabase.instance.client
                    .from('notifications')
                    .update({'is_read': true})
                    .eq('user_id', uid);
                setState(() {
                  for (final n in _realtimeNotifs) {
                    n['is_read'] = true;
                  }
                });
              } catch (_) {}
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Notifikasi Grup', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_realtimeNotifs.isEmpty)
            Text('Belum ada notifikasi.', style: TextStyle(color: Colors.grey.shade600)),
          if (_realtimeNotifs.isNotEmpty)
            ..._realtimeNotifs.take(20).map((n) {
              final title = n['title']?.toString() ?? 'Notifikasi';
              final body = n['body']?.toString() ?? '';
              final created = n['created_at']?.toString();
              final id = n['id']?.toString();
              final isRead = n['is_read'] == true;
              final type = n['type']?.toString();
              final data = _readData(n['data']);
              final memberId = data['member_id']?.toString();
              final groupName = data['group_name']?.toString() ?? 'Grup';
              return ListTile(
                leading: const Icon(Icons.notifications),
                title: Text(title, style: TextStyle(fontWeight: isRead ? FontWeight.normal : FontWeight.bold)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(body),
                    if (type == 'group_invite' && memberId != null && !isRead)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton(
                              onPressed: () async {
                                try {
                                  await GroupService.instance.respondToInvite(memberId, accept: false);
                                  if (id != null) {
                                    await Supabase.instance.client
                                        .from('notifications')
                                        .update({'is_read': true})
                                        .eq('id', id);
                                  }
                                  setState(() {
                                    n['is_read'] = true;
                                  });
                                } catch (_) {}
                              },
                              child: const Text('Tolak'),
                            ),
                            FilledButton(
                              onPressed: () async {
                                try {
                                  await GroupService.instance.respondToInvite(memberId, accept: true);
                                  if (id != null) {
                                    await Supabase.instance.client
                                        .from('notifications')
                                        .update({'is_read': true})
                                        .eq('id', id);
                                  }
                                  setState(() {
                                    n['is_read'] = true;
                                  });
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Bergabung ke $groupName')),
                                    );
                                  }
                                } catch (_) {}
                              },
                              child: const Text('Terima'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                trailing: created != null ? Text(created.split('T').first, style: const TextStyle(fontSize: 11)) : null,
                onTap: () async {
                  if (id == null) return;
                  try {
                    await Supabase.instance.client.from('notifications').update({'is_read': true}).eq('id', id);
                    setState(() {
                      n['is_read'] = true;
                    });
                  } catch (_) {}
                },
              );
            }),
          const SizedBox(height: 24),
          const Text('Pengingat', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Insight Harian'),
            subtitle: const Text('Dapatkan ringkasan keuangan setiap hari'),
            value: _dailyInsights,
            onChanged: _toggleDailyInsights,
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _sendTest,
            icon: const Icon(Icons.notifications_active),
            label: const Text('Kirim Notifikasi Test'),
          ),
          const SizedBox(height: 24),
          const Text(
            'Catatan: Pengingat harian berjalan di background. Insight detail akan tampil saat aplikasi aktif.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
