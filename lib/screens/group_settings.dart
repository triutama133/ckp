import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:catatan_keuangan_pintar/services/group_service.dart';
import 'package:catatan_keuangan_pintar/services/db_service.dart';

class GroupSettingsScreen extends StatefulWidget {
  final String groupId;
  final String currentUserId;

  const GroupSettingsScreen({Key? key, required this.groupId, this.currentUserId = 'local_user'}) : super(key: key);

  @override
  _GroupSettingsScreenState createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  List<GroupMember> _members = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() => _loading = true);
    final members = await GroupService.instance.getMembers(widget.groupId);
    setState(() {
      _members = members;
      _loading = false;
    });
  }

  Future<void> _promote(GroupMember m, String role) async {
    await GroupService.instance.promoteMember(m.id, role);
    await _loadMembers();
  }

  Future<void> _remove(GroupMember m) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text('Hapus member'),
      content: Text('Hapus ${m.userId} dari grup?'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Batal')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Hapus'))],
    ));
    if (ok == true) {
      await GroupService.instance.removeMember(m.id);
      await _loadMembers();
    }
  }

  Future<void> _createInvite() async {
    final invite = await GroupService.instance.generateInvite(widget.groupId, widget.currentUserId);
    await Clipboard.setData(ClipboardData(text: invite.token));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invite token disalin: ${invite.token}')));
  }

  Future<void> _showQrCode(String token) async {
    final deep = 'ckp://invite?token=$token';
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('QR Code Invite'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(
              data: deep,
              version: QrVersions.auto,
              size: 200.0,
              backgroundColor: Colors.white,
            ),
            const SizedBox(height: 16),
            Text('Token: $token', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            const Text('Scan QR code ini untuk bergabung', style: TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: deep));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link disalin ke clipboard')));
            },
            child: const Text('Copy Link'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup')),
        ],
      ),
    );
  }

  Future<void> _showInvites() async {
    final invites = await DBService.instance.getInvitesForGroup(widget.groupId);
    await showModalBottomSheet(context: context, builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: Text('Invites untuk grup')),
        ...invites.map((i) => ListTile(
          title: Text(i.token),
          subtitle: Text('Dibuat oleh: ${i.createdBy} • Exp: ${i.expiresAt ?? '-'}'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(icon: const Icon(Icons.qr_code), onPressed: () async { 
              await _showQrCode(i.token); 
            }),
            IconButton(icon: const Icon(Icons.copy), onPressed: () async { 
              await Clipboard.setData(ClipboardData(text: i.token)); 
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Token disalin'))); 
            }),
            IconButton(icon: const Icon(Icons.share), onPressed: () async {
              // create a deep-link and a web fallback link
              final deep = 'ckp://invite?token=${i.token}';
              final web = 'https://your-app.example.com/invite?token=${i.token}';
              final text = 'Anda diundang ke grup. Token: ${i.token}\nLink deep: $deep\nLink web: $web';
              await Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link invite disalin ke clipboard')));
            }),
            IconButton(icon: Icon(Icons.delete_forever), onPressed: () async {
              final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: const Text('Revoke Invite'), content: const Text('Batalkan invite ini?'), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Batal')), TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Revoke'))]));
              if (ok == true) {
                await GroupService.instance.revokeInvite(i.id);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite dicabut')));
                await _loadMembers();
                Navigator.of(ctx).pop();
                await _showInvites();
              }
            }),
          ]),
        )),
        const SizedBox(height:12),
      ]),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Pengaturan Grup'),
        actions: [
          IconButton(icon: Icon(Icons.person_add), onPressed: _createInvite, tooltip: 'Buat Invite'),
          IconButton(icon: Icon(Icons.list), onPressed: _showInvites, tooltip: 'Daftar Invite'),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadMembers,
                    child: ListView.builder(
                      itemCount: _members.length,
                      itemBuilder: (ctx, i) {
                        final m = _members[i];
                        return ListTile(
                          title: Text(m.userId),
                          subtitle: Text('Role: ${m.role} • Status: ${m.status}'),
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) async {
                              if (v == 'promote') await _promote(m, 'admin');
                              if (v == 'demote') await _promote(m, 'member');
                              if (v == 'remove') await _remove(m);
                            },
                            itemBuilder: (c) => [
                              PopupMenuItem(value: 'promote', child: Text('Promote ke Admin')),
                              PopupMenuItem(value: 'demote', child: Text('Demote ke Member')),
                              PopupMenuItem(value: 'remove', child: Text('Hapus Member')),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
          const Divider(height: 1.0),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(children: [
              ElevatedButton.icon(onPressed: () async {
                try {
                  await DBService.instance.leaveGroup(widget.groupId, widget.currentUserId);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Anda telah keluar dari grup')));
                  Navigator.of(context).pop(true);
                } catch (e) {
                  if (e.toString().contains('owner_cannot_leave')) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Anda adalah owner. Transfer ownership sebelum keluar.')));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal keluar: $e')));
                  }
                }
              }, icon: const Icon(Icons.exit_to_app), label: const Text('Keluar dari Grup')),
              const SizedBox(height:8),
              ElevatedButton.icon(onPressed: () async {
                // ownership transfer helper: pick a member to transfer to
                final members = await GroupService.instance.getMembers(widget.groupId);
                final choices = members.where((mm) => mm.userId != widget.currentUserId).toList();
                if (choices.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tidak ada anggota lain untuk ditransfer ownership')));
                  return;
                }
                final pick = await showDialog<GroupMember?>(
                  context: context,
                  builder: (ctx) => SimpleDialog(
                    title: const Text('Pilih anggota sebagai owner baru'),
                    children: choices.map((c) => SimpleDialogOption(
                      onPressed: () => Navigator.of(ctx).pop(c),
                      child: Text(c.userId),
                    )).toList(),
                  ),
                );
                if (pick != null) {
                  await DBService.instance.transferOwnership(widget.groupId, pick.id);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ownership berhasil dipindahkan')));
                  await _loadMembers();
                }
              }, icon: const Icon(Icons.swap_horiz), label: const Text('Transfer Ownership')),
            ]),
          ),
        ],
      ),
    );
  }
}
