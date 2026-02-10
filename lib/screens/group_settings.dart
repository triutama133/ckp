import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:catatan_keuangan_pintar/services/group_service.dart';
import 'package:catatan_keuangan_pintar/services/db_service.dart';
import 'package:catatan_keuangan_pintar/services/auth_service.dart';

class GroupSettingsScreen extends StatefulWidget {
  final String groupId;
  final String currentUserId;

  GroupSettingsScreen({Key? key, required this.groupId, String? currentUserId})
      : currentUserId = currentUserId ?? AuthService.instance.userId,
        super(key: key);

  @override
  _GroupSettingsScreenState createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  List<GroupMember> _members = [];
  bool _loading = true;
  String _groupName = 'Grup';

  @override
  void initState() {
    super.initState();
    _loadGroup();
    _loadMembers();
  }

  Future<void> _loadGroup() async {
    final groups = await DBService.instance.getGroups();
    final group = groups.where((g) => g.id == widget.groupId).toList();
    if (group.isNotEmpty) {
      setState(() {
        _groupName = group.first.name;
      });
    }
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

  Future<void> _inviteByEmail() async {
    final emailCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Undang via Email'),
        content: TextField(
          controller: emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email anggota',
            hintText: 'nama@email.com',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kirim')),
        ],
      ),
    );

    if (ok == true) {
      final email = emailCtrl.text.trim();
      try {
        await GroupService.instance.inviteByEmail(
          widget.groupId,
          widget.currentUserId,
          email,
          groupName: _groupName,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Undangan berhasil dikirim')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal mengundang: $e')),
          );
        }
      }
    }
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

  Future<void> _deleteGroup() async {
    final isOwner = _members.any((m) => m.userId == widget.currentUserId && m.role == 'owner');
    if (!isOwner) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hanya owner yang bisa menghapus grup')),
        );
      }
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Grup'),
        content: const Text('Semua data grup akan dihapus. Lanjutkan?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus')),
        ],
      ),
    );

    if (ok == true) {
      await DBService.instance.deleteGroup(widget.groupId);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Pengaturan Grup'),
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'invite') _createInvite();
              if (value == 'invite_email') _inviteByEmail();
              if (value == 'list') _showInvites();
              if (value == 'delete') _deleteGroup();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'invite',
                child: Row(
                  children: [
                    Icon(Icons.person_add, size: 20),
                    SizedBox(width: 12),
                    Text('Buat Invite'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'invite_email',
                child: Row(
                  children: [
                    Icon(Icons.email, size: 20),
                    SizedBox(width: 12),
                    Text('Undang via Email'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'list',
                child: Row(
                  children: [
                    Icon(Icons.list, size: 20),
                    SizedBox(width: 12),
                    Text('Daftar Invite'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_forever, size: 20, color: Colors.red),
                    SizedBox(width: 12),
                    Text('Hapus Grup'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Header Card
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.group,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Anggota Grup',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_members.length} anggota',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _createInvite,
                  icon: const Icon(Icons.person_add_alt_1),
                  color: Colors.white,
                  tooltip: 'Undang Anggota',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
              ],
            ),
          ),
          
          // Members List
          Expanded(
            child: _loading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Memuat anggota...'),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadMembers,
                    child: _members.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.people_outline, size: 64, color: Colors.grey.shade300),
                                const SizedBox(height: 16),
                                Text(
                                  'Belum ada anggota',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Undang anggota untuk bergabung',
                                  style: TextStyle(color: Colors.grey.shade500),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _members.length,
                            itemBuilder: (ctx, i) {
                              final m = _members[i];
                              final isOwner = m.role == 'owner';
                              final isAdmin = m.role == 'admin';
                              
                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: BorderSide(
                                    color: isOwner
                                        ? Colors.amber.shade200
                                        : isAdmin
                                            ? Colors.blue.shade200
                                            : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.all(16),
                                  leading: Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: isOwner
                                            ? [Colors.amber.shade400, Colors.amber.shade600]
                                            : isAdmin
                                                ? [Colors.blue.shade400, Colors.blue.shade600]
                                                : [Colors.grey.shade400, Colors.grey.shade600],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        m.userId.substring(0, 1).toUpperCase(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          m.userId,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                      if (isOwner)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.amber.shade100,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.star, size: 14, color: Colors.amber.shade700),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Owner',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.amber.shade700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      else if (isAdmin)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.shade100,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.admin_panel_settings, size: 14, color: Colors.blue.shade700),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Admin',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.blue.shade700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      children: [
                                        Icon(
                                          m.status == 'active'
                                              ? Icons.check_circle
                                              : m.status == 'pending'
                                                  ? Icons.schedule
                                                  : Icons.cancel,
                                          size: 14,
                                          color: m.status == 'active'
                                              ? Colors.green
                                              : m.status == 'pending'
                                                  ? Colors.orange
                                                  : Colors.red,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          m.status == 'active'
                                              ? 'Aktif'
                                              : m.status == 'pending'
                                                  ? 'Menunggu'
                                                  : 'Nonaktif',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: m.status == 'active'
                                                ? Colors.green.shade700
                                                : m.status == 'pending'
                                                    ? Colors.orange.shade700
                                                    : Colors.red.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  trailing: !isOwner
                                      ? PopupMenuButton<String>(
                                          icon: const Icon(Icons.more_vert),
                                          onSelected: (v) async {
                                            if (v == 'promote') await _promote(m, 'admin');
                                            if (v == 'demote') await _promote(m, 'member');
                                            if (v == 'remove') await _remove(m);
                                          },
                                          itemBuilder: (c) => [
                                            if (m.role != 'admin')
                                              const PopupMenuItem(
                                                value: 'promote',
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.arrow_upward, size: 18),
                                                    SizedBox(width: 8),
                                                    Text('Jadikan Admin'),
                                                  ],
                                                ),
                                              ),
                                            if (m.role == 'admin')
                                              const PopupMenuItem(
                                                value: 'demote',
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.arrow_downward, size: 18),
                                                    SizedBox(width: 8),
                                                    Text('Turunkan ke Member'),
                                                  ],
                                                ),
                                              ),
                                            const PopupMenuItem(
                                              value: 'remove',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.person_remove, size: 18, color: Colors.red),
                                                  SizedBox(width: 8),
                                                  Text('Hapus Member', style: TextStyle(color: Colors.red)),
                                                ],
                                              ),
                                            ),
                                          ],
                                        )
                                      : null,
                                ),
                              );
                            },
                          ),
                  ),
          ),
          
          // Actions Section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final members = await GroupService.instance.getMembers(widget.groupId);
                        final choices = members.where((mm) => mm.userId != widget.currentUserId).toList();
                        
                        if (choices.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Tidak ada anggota lain untuk ditransfer ownership'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }
                        
                        final pick = await showDialog<GroupMember?>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Transfer Ownership'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Pilih anggota sebagai owner baru:'),
                                const SizedBox(height: 12),
                                ...choices.map((c) => ListTile(
                                  leading: CircleAvatar(
                                    child: Text(c.userId.substring(0, 1).toUpperCase()),
                                  ),
                                  title: Text(c.userId),
                                  subtitle: Text(c.role),
                                  onTap: () => Navigator.of(ctx).pop(c),
                                )),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Batal'),
                              ),
                            ],
                          ),
                        );
                        
                        if (pick != null && context.mounted) {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Konfirmasi'),
                              content: Text('Transfer ownership ke ${pick.userId}? Anda akan menjadi admin.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
                                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Transfer')),
                              ],
                            ),
                          );
                          
                          if (confirm == true) {
                            await DBService.instance.transferOwnership(widget.groupId, pick.id);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Row(
                                    children: [
                                      Icon(Icons.check_circle, color: Colors.white),
                                      SizedBox(width: 12),
                                      Text('Ownership berhasil dipindahkan'),
                                    ],
                                  ),
                                  backgroundColor: Colors.green,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                            await _loadMembers();
                          }
                        }
                      },
                      icon: const Icon(Icons.swap_horiz),
                      label: const Text('Transfer Ownership'),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Keluar dari Grup'),
                            content: const Text('Anda yakin ingin keluar dari grup ini?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                child: const Text('Keluar'),
                              ),
                            ],
                          ),
                        );
                        
                        if (confirm == true && context.mounted) {
                          try {
                            await DBService.instance.leaveGroup(widget.groupId, widget.currentUserId);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Anda telah keluar dari grup'),
                                  backgroundColor: Colors.green,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                              Navigator.of(context).pop(true);
                            }
                          } catch (e) {
                            if (context.mounted) {
                              if (e.toString().contains('owner_cannot_leave')) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Anda adalah owner. Transfer ownership terlebih dahulu.'),
                                    backgroundColor: Colors.orange,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Gagal keluar: $e'),
                                    backgroundColor: Colors.red,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            }
                          }
                        }
                      },
                      icon: const Icon(Icons.exit_to_app),
                      label: const Text('Keluar dari Grup'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
