import 'package:flutter/material.dart';
import 'package:catatan_keuangan_pintar/services/group_service.dart';
import 'package:catatan_keuangan_pintar/services/db_service.dart';

class AcceptInviteScreen extends StatefulWidget {
  final String currentUserId;
  const AcceptInviteScreen({Key? key, this.currentUserId = 'local_user'}) : super(key: key);

  @override
  _AcceptInviteScreenState createState() => _AcceptInviteScreenState();
}

class _AcceptInviteScreenState extends State<AcceptInviteScreen> {
  final _controller = TextEditingController();
  bool _loading = false;

  Future<void> _accept() async {
    final token = _controller.text.trim();
    if (token.isEmpty) return;
    setState(() => _loading = true);
    try {
      final member = await GroupService.instance.acceptInvite(token, widget.currentUserId);
      if (member == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Token invalid atau kadaluarsa')));
      } else {
        // Optionally refresh local groups: if group doesn't exist locally, try to create a placeholder
        // If group exists, nothing; otherwise, leave it up to remote sync later.
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite diterima. Anda sekarang anggota grup.')));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menerima invite: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Terima Invite')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Tempel token invite di bawah ini dan tekan Terima.'),
            const SizedBox(height: 12),
            TextField(controller: _controller, decoration: const InputDecoration(labelText: 'Token invite', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loading ? null : _accept, child: _loading ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Terima')),
          ],
        ),
      ),
    );
  }
}
