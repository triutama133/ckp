import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:catatan_keuangan_pintar/services/parser_service.dart';
import 'package:catatan_keuangan_pintar/services/db_service.dart';
import 'package:catatan_keuangan_pintar/screens/group_settings.dart';
import 'package:catatan_keuangan_pintar/screens/accept_invite.dart';
import 'package:intl/intl.dart';

class ChatScreen extends HookWidget {
  ChatScreen({super.key});

  final _uuid = const Uuid();

  @override
  Widget build(BuildContext context) {
    final controller = useTextEditingController();
    final nf = NumberFormat('#,##0', 'id');

    // Local in-memory messages + AnimatedList key for smooth insert animations
    final messagesState = useState<List<Message>>(<Message>[]);
    final listKey = useRef<GlobalKey<AnimatedListState>>(GlobalKey<AnimatedListState>());
    final scrollController = useScrollController();
    final inputScrollController = useScrollController();
    final pendingBatch = useRef<Map<String, dynamic>?>(null);
    final pendingDelete = useRef<Map<String, dynamic>?>(null);

    final groupsState = useState<List<Group>>(<Group>[]);
    final selectedGroupId = useState<String?>(null); // null = personal

    const _prefKeySelectedGroup = 'selectedGroupId';

    // initial load: load groups and messages for selected chat
    useEffect(() {
      Future<void> _init() async {
        final prefs = await SharedPreferences.getInstance();
        final stored = prefs.getString(_prefKeySelectedGroup);
        selectedGroupId.value = stored;

        final gs = await DBService.instance.getGroups();
        groupsState.value = gs;

        final list = await DBService.instance.getMessagesForGroup(selectedGroupId.value);
        messagesState.value = [];
        WidgetsBinding.instance.addPostFrameCallback((_) {
          for (final m in list.reversed) {
            messagesState.value = [m, ...messagesState.value];
            listKey.value.currentState?.insertItem(0, duration: Duration.zero);
          }
        });
      }
      _init();
      return null;
    }, const []);

    // helper to send system reply and persist it (optionally for a group)
    Future<void> sendSystemReply(String reply, {TransactionModel? tx, String? groupId}) async {
      final sysMsg = Message(
        id: _uuid.v4(),
        text: reply,
        createdAt: DateTime.now(),
        parsedTransaction: tx,
        isSystem: true,
        groupId: groupId,
      );
      await DBService.instance.insertMessage(sysMsg);
      messagesState.value = [sysMsg, ...messagesState.value];
      listKey.value.currentState?.insertItem(0, duration: const Duration(milliseconds: 300));
      // ensure the list scrolls to show the newest message (AnimatedList is reversed)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          scrollController.animateTo(0.0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        } catch (_) {}
      });
    }

    return Column(
      children: [
        // Chat selector (Personal + Groups)
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
                const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Buat grup baru',
                onPressed: () async {
                  // show create group dialog
                  final nameCtrl = TextEditingController();
                  final descCtrl = TextEditingController();
                  final res = await showDialog<bool?>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Buat Grup Baru'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nama grup')),
                          TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Deskripsi (opsional)')),
                        ],
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Batal')),
                        ElevatedButton(
                          onPressed: () async {
                            final name = nameCtrl.text.trim();
                            if (name.isEmpty) return;
                            final id = _uuid.v4();
                            final g = Group(id: id, name: name, description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(), icon: null, createdAt: DateTime.now(), createdBy: 'local_user');
                            await DBService.instance.insertGroup(g);
                            final gs2 = await DBService.instance.getGroups();
                            groupsState.value = gs2;
                            selectedGroupId.value = id;
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString(_prefKeySelectedGroup, id);
                            // load messages for new group
                            final list2 = await DBService.instance.getMessagesForGroup(id);
                            messagesState.value = [];
                            for (final m in list2.reversed) {
                              messagesState.value = [m, ...messagesState.value];
                              listKey.value.currentState?.insertItem(0, duration: Duration.zero);
                            }
                            Navigator.of(ctx).pop(true);
                          },
                          child: const Text('Buat'),
                        ),
                      ],
                    ),
                  );
                  if (res == true) {
                    // created and already selected
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.input),
                tooltip: 'Terima invite',
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AcceptInviteScreen()));
                  // after returning, refresh groups
                  final gs2 = await DBService.instance.getGroups();
                  groupsState.value = gs2;
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Personal'),
                selected: selectedGroupId.value == null,
                onSelected: (_) async {
                  selectedGroupId.value = null;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove(_prefKeySelectedGroup);
                  final list = await DBService.instance.getMessagesForGroup(null);
                  messagesState.value = [];
                  for (final m in list.reversed) {
                    messagesState.value = [m, ...messagesState.value];
                  }
                },
              ),
              const SizedBox(width: 8),
              ...groupsState.value.map((g) => Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: GestureDetector(
                      onLongPress: () async {
                        // edit / delete options
                        final choice = await showModalBottomSheet<String?>(
                          context: context,
                          builder: (ctx) => SafeArea(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.edit),
                                  title: const Text('Ubah nama grup'),
                                  onTap: () => Navigator.of(ctx).pop('edit'),
                                ),
                                ListTile(
                                  leading: const Icon(Icons.group),
                                  title: const Text('Kelola anggota'),
                                  onTap: () => Navigator.of(ctx).pop('settings'),
                                ),
                                ListTile(
                                  leading: const Icon(Icons.delete_forever),
                                  title: const Text('Hapus grup'),
                                  onTap: () => Navigator.of(ctx).pop('delete'),
                                ),
                                ListTile(
                                  leading: const Icon(Icons.close),
                                  title: const Text('Tutup'),
                                  onTap: () => Navigator.of(ctx).pop(null),
                                ),
                              ],
                            ),
                          ),
                        );
                        if (choice == 'edit') {
                          final nameCtrl = TextEditingController(text: g.name);
                          final descCtrl = TextEditingController(text: g.description ?? '');
                          final ok = await showDialog<bool?>(
                            context: context,
                            builder: (dctx) => AlertDialog(
                              title: const Text('Ubah Grup'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nama grup')),
                                  TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Deskripsi (opsional)')),
                                ],
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.of(dctx).pop(false), child: const Text('Batal')),
                                ElevatedButton(
                                  onPressed: () async {
                                    final updated = Group(id: g.id, name: nameCtrl.text.trim(), description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(), icon: g.icon, createdAt: g.createdAt, createdBy: g.createdBy);
                                    await DBService.instance.updateGroup(updated);
                                    final gs2 = await DBService.instance.getGroups();
                                    groupsState.value = gs2;
                                    Navigator.of(dctx).pop(true);
                                  },
                                  child: const Text('Simpan'),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) return;
                        }
                        if (choice == 'settings') {
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => GroupSettingsScreen(groupId: g.id, currentUserId: 'local_user')));
                          return;
                        }
                        if (choice == 'delete') {
                          final confirm = await showDialog<bool?>(
                            context: context,
                            builder: (dctx) => AlertDialog(
                              title: const Text('Konfirmasi Hapus'),
                              content: Text('Hapus grup "${g.name}"? Semua pesan grup akan dihapus.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.of(dctx).pop(false), child: const Text('Batal')),
                                ElevatedButton(
                                  onPressed: () async {
                                    await DBService.instance.deleteGroup(g.id);
                                    final prefs = await SharedPreferences.getInstance();
                                    if (prefs.getString(_prefKeySelectedGroup) == g.id) {
                                      await prefs.remove(_prefKeySelectedGroup);
                                      selectedGroupId.value = null;
                                    }
                                    final gs2 = await DBService.instance.getGroups();
                                    groupsState.value = gs2;
                                    final list2 = await DBService.instance.getMessagesForGroup(selectedGroupId.value);
                                    messagesState.value = [];
                                    for (final m in list2.reversed) {
                                      messagesState.value = [m, ...messagesState.value];
                                    }
                                    Navigator.of(dctx).pop(true);
                                  },
                                  child: const Text('Hapus'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) return;
                        }
                      },
                      child: ChoiceChip(
                        label: Text(g.name),
                        selected: selectedGroupId.value == g.id,
                        onSelected: (_) async {
                          selectedGroupId.value = g.id;
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString(_prefKeySelectedGroup, g.id);
                          final list = await DBService.instance.getMessagesForGroup(g.id);
                          messagesState.value = [];
                          for (final m in list.reversed) {
                            messagesState.value = [m, ...messagesState.value];
                          }
                        },
                      ),
                    ),
                  ))
            ],
          ),
        ),
        Expanded(
          child: AnimatedList(
            key: listKey.value,
            reverse: true,
            controller: scrollController,
            initialItemCount: messagesState.value.length,
            itemBuilder: (context, index, animation) {
              final msg = messagesState.value[index];
              return SizeTransition(
                sizeFactor: animation,
                axisAlignment: 0.0,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                  child: Row(
                    mainAxisAlignment: msg.isSystem ? MainAxisAlignment.start : MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (msg.isSystem) ...[
                        const CircleAvatar(radius: 14, child: Icon(Icons.computer, size: 16)),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Container(
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                          decoration: BoxDecoration(
                            color: msg.isSystem ? Colors.grey.shade200 : Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(12),
                              topRight: const Radius.circular(12),
                              bottomLeft: Radius.circular(msg.isSystem ? 0 : 12),
                              bottomRight: Radius.circular(msg.isSystem ? 12 : 0),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                msg.text,
                                style: TextStyle(
                                  color: msg.isSystem ? Colors.black87 : Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                              if (msg.parsedTransaction != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Rincian: ${nf.format(msg.parsedTransaction!.amount)} - ${msg.parsedTransaction!.category ?? "-"}',
                                  style: TextStyle(fontSize: 13, color: msg.isSystem ? Colors.black54 : Colors.white70),
                                ),
                              ],
                              const SizedBox(height: 6),
                              Text(
                                DateFormat('dd MMM yyyy HH:mm').format(msg.createdAt),
                                style: TextStyle(fontSize: 11, color: msg.isSystem ? Colors.black45 : Colors.white70),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (!msg.isSystem) const SizedBox(width: 8),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
          child: Row(
            children: [
              IconButton(
                onPressed: () async {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('STT offline not yet implemented')));
                },
                icon: const Icon(Icons.mic),
              ),
              IconButton(
                onPressed: () async {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('OCR not yet implemented')));
                },
                icon: const Icon(Icons.camera_alt),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 6,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  scrollController: inputScrollController,
                  decoration: const InputDecoration.collapsed(hintText: 'Ketik pesan, mis: "Beli sembako 250000"'),
                ),
              ),
              IconButton(
                onPressed: () async {
                  final text = controller.text.trim();
                  if (text.isEmpty) return;
                  final lower = text.toLowerCase();
                   final id = _uuid.v4();
                   final timestamp = DateTime.now();

                  // Insert user message immediately so it appears in the chat
                  final userMsg = Message(id: id, text: text, createdAt: timestamp, parsedTransaction: null, isSystem: false, groupId: selectedGroupId.value);
                  await DBService.instance.insertMessage(userMsg);
                  messagesState.value = [userMsg, ...messagesState.value];
                  listKey.value.currentState?.insertItem(0, duration: const Duration(milliseconds: 200));
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    try { scrollController.animateTo(0.0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut); } catch (_) {}
                  });

                  // If there's a pending batch awaiting confirmation, handle confirmation commands
                  if (pendingBatch.value != null && (lower == 'simpan' || lower == 'ya' || lower == 'lanjut')) {
                    final batch = pendingBatch.value!;
                    final parsedList = batch['parsed'] as List<dynamic>;
                    final recorded = <String>[];
                    for (final parsedPart in parsedList) {
                      final descLower = (parsedPart.description ?? '').toLowerCase();
                      final isAssetType = parsedPart.type == 'saving' || parsedPart.type == 'investment';
                      final withdrawalPhrases = ['ambil', 'dari', 'tarik', 'pakai', 'gunakan', 'ambil dari'];
                      final isWithdrawal = isAssetType && withdrawalPhrases.any((p) => descLower.contains(p));

                      if (isWithdrawal) {
                        final assetOutType = '${parsedPart.type}_out';
                        final assetTx = TransactionModel(
                          id: _uuid.v4(),
                          messageId: id,
                          amount: parsedPart.amount,
                          currency: parsedPart.currency ?? 'IDR',
                          category: parsedPart.category ?? (parsedPart.type == 'saving' ? 'Tabungan' : 'Investasi'),
                          description: parsedPart.description,
                          date: parsedPart.date ?? timestamp,
                          createdAt: timestamp,
                          isIncome: false,
                          type: assetOutType,
                          scope: parsedPart.scope ?? 'personal',
                          groupId: selectedGroupId.value,
                        );
                        await DBService.instance.insertTransaction(assetTx);

                        final cashTx = TransactionModel(
                          id: _uuid.v4(),
                          messageId: id,
                          amount: parsedPart.amount,
                          currency: parsedPart.currency ?? 'IDR',
                          category: 'Transfer dari ${parsedPart.type}',
                          description: 'Transfer dari ${parsedPart.type}: ${parsedPart.description}',
                          date: parsedPart.date ?? timestamp,
                          createdAt: timestamp,
                          isIncome: false,
                          type: 'transfer_in',
                          scope: parsedPart.scope ?? 'personal',
                          groupId: selectedGroupId.value,
                        );
                        await DBService.instance.insertTransaction(cashTx);

                        recorded.add('Penarikan dari ${parsedPart.type}: Rp ${nf.format(parsedPart.amount)}');
                      } else {
                        final tx = TransactionModel(
                          id: _uuid.v4(),
                          messageId: id,
                          amount: parsedPart.amount,
                          currency: parsedPart.currency ?? 'IDR',
                          category: parsedPart.category,
                          description: parsedPart.description,
                          date: parsedPart.date ?? timestamp,
                          createdAt: timestamp,
                          isIncome: parsedPart.isIncome,
                          type: parsedPart.type,
                          scope: parsedPart.scope ?? 'personal',
                          groupId: selectedGroupId.value,
                        );
                        await DBService.instance.insertTransaction(tx);
                        final label = parsedPart.type == 'saving'
                            ? 'Tabungan'
                            : parsedPart.type == 'investment'
                                ? 'Investasi'
                                : (parsedPart.isIncome ? 'Pendapatan' : 'Pengeluaran');
                        recorded.add('$label: Rp ${nf.format(parsedPart.amount)}');
                      }
                    }

                    // Totals for current month
                    final monthStart = DateTime(timestamp.year, timestamp.month, 1);
                    final monthEnd = DateTime(timestamp.year, timestamp.month + 1, 1).subtract(const Duration(milliseconds: 1));
                    final totals = await DBService.instance.getTotalsBetween(monthStart, monthEnd);
                    final income = (totals['income'] as num).toDouble();
                    final expense = (totals['expense'] as num).toDouble();
                    final saving = (totals['saving'] as num).toDouble();
                    final investment = (totals['investment'] as num).toDouble();
                    final balance = (totals['balance'] as num).toDouble();

                    final sb = StringBuffer();
                    sb.writeln('Pencatatan batch (${parsedList.length} transaksi):');
                    for (final r in recorded) sb.writeln('  • $r');
                    sb.writeln('- Ringkasan bulan ini:');
                    sb.writeln('  • Pendapatan: Rp ${nf.format(income)}');
                    sb.writeln('  • Pengeluaran: Rp ${nf.format(expense)}');
                    sb.writeln('  • Tabungan: Rp ${nf.format(saving)}');
                    sb.writeln('  • Investasi: Rp ${nf.format(investment)}');
                    sb.writeln('  • Saldo bersih: Rp ${nf.format(balance)}');

                    pendingBatch.value = null;
                    await sendSystemReply(sb.toString(), groupId: selectedGroupId.value);
                    controller.clear();
                    return;
                  }

                  // If there's a pending delete awaiting confirmation
                  if (pendingDelete.value != null) {
                    final confirmWords = ['hapus', 'ya', 'konfirmasi', 'confirm'];
                    final cancelWords = ['batal', 'cancel', 'tidak', 'ngecancel'];
                    if (confirmWords.any((w) => lower == w || lower.contains(w))) {
                      final batch = pendingDelete.value!;
                      final ids = (batch['ids'] as List<String>?) ?? <String>[];
                      if (ids.isEmpty) {
                        await sendSystemReply('Tidak ada transaksi untuk dihapus.', groupId: selectedGroupId.value);
                        pendingDelete.value = null;
                        controller.clear();
                        return;
                      }

                      await DBService.instance.deleteTransactionsSoft(ids);

                      // Provide feedback
                      final monthStart = DateTime(timestamp.year, timestamp.month, 1);
                      final monthEnd = DateTime(timestamp.year, timestamp.month + 1, 1).subtract(const Duration(milliseconds: 1));
                      final totals = await DBService.instance.getTotalsBetween(monthStart, monthEnd);
                      final income = (totals['income'] as num).toDouble();
                      final expense = (totals['expense'] as num).toDouble();
                      final saving = (totals['saving'] as num).toDouble();
                      final investment = (totals['investment'] as num).toDouble();
                      final balance = (totals['balance'] as num).toDouble();

                      final sb = StringBuffer();
                      sb.writeln('Berhasil menghapus ${ids.length} transaksi (soft-delete).');
                      sb.writeln('- Ringkasan bulan ini setelah penghapusan:');
                      sb.writeln('  • Pendapatan: Rp ${nf.format(income)}');
                      sb.writeln('  • Pengeluaran: Rp ${nf.format(expense)}');
                      sb.writeln('  • Tabungan: Rp ${nf.format(saving)}');
                      sb.writeln('  • Investasi: Rp ${nf.format(investment)}');
                      sb.writeln('  • Saldo bersih: Rp ${nf.format(balance)}');

                      pendingDelete.value = null;
                      await sendSystemReply(sb.toString(), groupId: selectedGroupId.value);
                      controller.clear();
                      return;
                    }

                    if (cancelWords.any((w) => lower == w || lower.contains(w))) {
                      pendingDelete.value = null;
                      await sendSystemReply('Perintah penghapusan dibatalkan. Tidak ada data yang dihapus.', groupId: selectedGroupId.value);
                      controller.clear();
                      return;
                    }
                    // otherwise fallthrough and let user answer normally
                  }

                  // Use unified intent parser (offline rule-based)
                  final intentRes = await ParserService.instance.parseIntent(text);
                  Map<String, dynamic>? intentMap;
                  try {
                    intentMap = intentRes as Map<String, dynamic>?;
                  } catch (_) {
                    intentMap = null;
                  }

                  // If parser suggested a groupId for shared intent, select and persist it,
                  // and update the already-inserted user message to belong to that group.
                  if (intentMap != null && intentMap['groupId'] != null) {
                    final suggestedGroup = intentMap['groupId'] as String?;
                    if (suggestedGroup != null) {
                      try {
                        selectedGroupId.value = suggestedGroup;
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString(_prefKeySelectedGroup, suggestedGroup);

                        // update stored user message to have the groupId
                        final idx = messagesState.value.indexWhere((m) => m.id == id);
                        if (idx != -1) {
                          final old = messagesState.value[idx];
                          final updatedMsg = Message(id: old.id, text: old.text, createdAt: old.createdAt, parsedTransaction: old.parsedTransaction, isSystem: old.isSystem, groupId: suggestedGroup);
                          await DBService.instance.insertMessage(updatedMsg);
                          final newList = [...messagesState.value];
                          newList[idx] = updatedMsg;
                          messagesState.value = newList;
                        }
                      } catch (_) {}
                    }
                  }

                  if (intentMap != null) {
                    final intent = (intentMap['intent'] as String?) ?? 'unknown';

                    // Handle delete intent via unified parser
                    if (intent == 'delete') {
                      final deleteSpec = intentMap['deleteSpec'] ?? intentMap['delete'] ?? <String, dynamic>{};
                      List<TransactionModel> txs = [];
                      final mode = (deleteSpec['mode'] as String?) ?? 'range';
                      if (mode == 'last') {
                        final count = (deleteSpec['count'] as int?) ?? 1;
                        txs = await DBService.instance.getRecentTransactions(count);
                      } else if (mode == 'range') {
                        final start = (deleteSpec['start'] as DateTime?) ?? DateTime.fromMillisecondsSinceEpoch(0);
                        final end = (deleteSpec['end'] as DateTime?) ?? DateTime.now();
                        txs = await DBService.instance.getTransactionsBetween(start, end);
                      } else if (mode == 'all') {
                        txs = await DBService.instance.getTransactionsBetween(DateTime.fromMillisecondsSinceEpoch(0), DateTime.now());
                      }

                      if (txs.isEmpty) {
                        await sendSystemReply('Tidak ada transaksi yang cocok untuk dihapus.', groupId: selectedGroupId.value);
                        controller.clear();
                        return;
                      }

                      final ids = txs.map((t) => t.id).toList();
                      pendingDelete.value = {'ids': ids, 'txs': txs};
                      final sb = StringBuffer();
                      sb.writeln('Perintah penghapusan terdeteksi. Anda akan menghapus ${txs.length} transaksi:');
                      var i = 1;
                      for (final t in txs) {
                        sb.writeln('  ${i++}. ${DateFormat('dd/MM/yyyy').format(t.date)} - ${t.category ?? '-'} - Rp ${nf.format(t.amount)} - ${t.type ?? (t.isIncome ? 'Pendapatan' : 'Pengeluaran')}');
                        if (i > 20) break; // show up to 20
                      }
                      if (txs.length > 20) sb.writeln('  ...dan ${txs.length - 20} transaksi lainnya');
                      sb.writeln('\nBalas dengan "hapus" untuk konfirmasi atau "batal" untuk membatalkan.');

                      await sendSystemReply(sb.toString(), groupId: selectedGroupId.value);
                      controller.clear();
                      return;
                    }

                    // Handle create intent (single or multiple transactions)
                    if (intent == 'create') {
                      final txs = (intentMap['transactions'] as List<dynamic>?) ??
                          (intentMap['transaction'] != null ? [intentMap['transaction']] : <dynamic>[]);
                      if (txs.isNotEmpty) {
                        final recorded = <String>[];
                        TransactionModel? representativeTx;
                        for (final parsedPart in txs) {
                          final descLower = (parsedPart.description ?? '').toString().toLowerCase();
                          final isAssetType = parsedPart.type == 'saving' || parsedPart.type == 'investment';
                          final withdrawalPhrases = ['ambil', 'dari', 'tarik', 'pakai', 'gunakan', 'ambil dari'];
                          final isWithdrawal = isAssetType && withdrawalPhrases.any((p) => descLower.contains(p));

                          if (isWithdrawal) {
                            final assetOutType = '${parsedPart.type}_out';
                            final assetTx = TransactionModel(
                              id: _uuid.v4(),
                              messageId: id,
                              amount: parsedPart.amount,
                              currency: parsedPart.currency ?? 'IDR',
                              category: parsedPart.category ?? (parsedPart.type == 'saving' ? 'Tabungan' : 'Investasi'),
                              description: parsedPart.description,
                              date: parsedPart.date ?? timestamp,
                              createdAt: timestamp,
                              isIncome: false,
                              type: assetOutType,
                              scope: parsedPart.scope ?? 'personal',
                              groupId: selectedGroupId.value,
                            );
                            await DBService.instance.insertTransaction(assetTx);

                            final cashTx = TransactionModel(
                              id: _uuid.v4(),
                              messageId: id,
                              amount: parsedPart.amount,
                              currency: parsedPart.currency ?? 'IDR',
                              category: 'Transfer dari ${parsedPart.type}',
                              description: 'Transfer dari ${parsedPart.type}: ${parsedPart.description}',
                              date: parsedPart.date ?? timestamp,
                              createdAt: timestamp,
                              isIncome: false,
                              type: 'transfer_in',
                              scope: parsedPart.scope ?? 'personal',
                              groupId: selectedGroupId.value,
                            );
                            await DBService.instance.insertTransaction(cashTx);

                            recorded.add('Penarikan dari ${parsedPart.type}: Rp ${nf.format(parsedPart.amount)}');
                            representativeTx ??= assetTx;
                          } else {
                            final tx = TransactionModel(
                              id: _uuid.v4(),
                              messageId: id,
                              amount: parsedPart.amount,
                              currency: parsedPart.currency ?? 'IDR',
                              category: parsedPart.category,
                              description: parsedPart.description,
                              date: parsedPart.date ?? timestamp,
                              createdAt: timestamp,
                              isIncome: parsedPart.isIncome,
                              type: parsedPart.type,
                              scope: parsedPart.scope ?? 'personal',
                              groupId: selectedGroupId.value,
                            );
                            await DBService.instance.insertTransaction(tx);
                            representativeTx ??= tx;
                            final label = parsedPart.type == 'saving'
                                ? 'Tabungan'
                                : parsedPart.type == 'investment'
                                    ? 'Investasi'
                                    : (parsedPart.isIncome ? 'Pendapatan' : 'Pengeluaran');
                            recorded.add('$label: Rp ${nf.format(parsedPart.amount)}');
                          }
                        }

                        // Attach representative transaction to user message (if any)
                        if (representativeTx != null) {
                          try {
                            final idx = messagesState.value.indexWhere((m) => m.id == id);
                            if (idx != -1) {
                              final old = messagesState.value[idx];
                              final updated = Message(id: old.id, text: old.text, createdAt: old.createdAt, parsedTransaction: representativeTx, isSystem: old.isSystem, groupId: old.groupId);
                              final newList = [...messagesState.value];
                              newList[idx] = updated;
                              messagesState.value = newList;
                            }
                          } catch (_) {}
                        }

                        // Totals for current month
                        final monthStart = DateTime(timestamp.year, timestamp.month, 1);
                        final monthEnd = DateTime(timestamp.year, timestamp.month + 1, 1).subtract(const Duration(milliseconds: 1));
                        final totals = await DBService.instance.getTotalsBetween(monthStart, monthEnd);
                        final income = (totals['income'] as num).toDouble();
                        final expense = (totals['expense'] as num).toDouble();
                        final saving = (totals['saving'] as num).toDouble();
                        final investment = (totals['investment'] as num).toDouble();
                        final balance = (totals['balance'] as num).toDouble();

                        final sb = StringBuffer();
                        sb.writeln('Pencatatan (${txs.length} transaksi) berhasil:');
                        for (final r in recorded) sb.writeln('  • $r');
                        sb.writeln('- Ringkasan bulan ini:');
                        sb.writeln('  • Pendapatan: Rp ${nf.format(income)}');
                        sb.writeln('  • Pengeluaran: Rp ${nf.format(expense)}');
                        sb.writeln('  • Tabungan: Rp ${nf.format(saving)}');
                        sb.writeln('  • Investasi: Rp ${nf.format(investment)}');
                        sb.writeln('  • Saldo bersih: Rp ${nf.format(balance)}');

                        await sendSystemReply(sb.toString(), groupId: selectedGroupId.value);
                        controller.clear();
                        return;
                      }
                    }

                    // Handle summary/list intents if parseIntent provided period info
                    if (intent == 'summary' || intent == 'list') {
                      final period = intentMap['period'] as Map<String, dynamic>?;
                      DateTime start;
                      DateTime end;
                      String periodLabel = '';

                      if (period != null && period['start'] != null && period['end'] != null) {
                        start = period['start'] as DateTime;
                        end = period['end'] as DateTime;
                        periodLabel = (period['label'] as String?) ?? '';
                      } else {
                        // default to current month for summaries; for list default to recent N
                        final now = DateTime.now();
                        start = DateTime(now.year, now.month, 1);
                        end = DateTime(now.year, now.month + 1, 1).subtract(const Duration(milliseconds: 1));
                        periodLabel = lower.contains('hari ini') ? 'hari ini' : 'bulan ini';
                      }

                      if (intent == 'summary') {
                        final totals = await DBService.instance.getTotalsBetween(start, end);
                        final income = (totals['income'] as num).toDouble();
                        final expense = (totals['expense'] as num).toDouble();
                        final saving = (totals['saving'] as num).toDouble();
                        final investment = (totals['investment'] as num).toDouble();
                        final balance = (totals['balance'] as num).toDouble();
                        final count = totals['count'] as int;

                        final buffer = StringBuffer();
                        buffer.writeln('- Ringkasan (${periodLabel.isNotEmpty ? periodLabel : 'periode'}):');
                        buffer.writeln('  • Pendapatan: Rp ${nf.format(income)}');
                        buffer.writeln('  • Pengeluaran: Rp ${nf.format(expense)}');
                        buffer.writeln('  • Tabungan: Rp ${nf.format(saving)}');
                        buffer.writeln('  • Investasi: Rp ${nf.format(investment)}');
                        buffer.writeln('  • Saldo bersih: Rp ${nf.format(balance)}');
                        buffer.writeln('  • Total transaksi: $count');

                        await sendSystemReply(buffer.toString(), groupId: selectedGroupId.value);
                        controller.clear();
                        return;
                      }

                      if (intent == 'list') {
                        List<TransactionModel> txs = [];
                        final periodProvided = period != null && period['start'] != null && period['end'] != null;
                        if (periodProvided) {
                          txs = await DBService.instance.getTransactionsBetween(start, end);
                        } else {
                          final count = (intentMap['count'] as int?) ?? 10;
                          txs = await DBService.instance.getRecentTransactions(count);
                        }

                        if (txs.isEmpty) {
                          await sendSystemReply('Tidak ada transaksi ditemukan untuk periode yang diminta.', groupId: selectedGroupId.value);
                        } else {
                          final buffer = StringBuffer();
                          for (final t in txs) {
                            buffer.writeln('${DateFormat('dd/MM').format(t.date)} - ${t.category ?? '-'} - Rp ${nf.format(t.amount)} - ${t.type ?? (t.isIncome ? 'Pendapatan' : 'Pengeluaran')}');
                          }
                          if (!(period != null && period['start'] != null) && txs.length == ((intentMap['count'] as int?) ?? 10)) buffer.writeln('...dan transaksi lainnya.');
                          await sendSystemReply(buffer.toString(), groupId: selectedGroupId.value);
                        }

                        controller.clear();
                        return;
                      }
                    }
                  }

                  // Quick rule-based parse
                  final parsed = await ParserService.instance.parseText(text);

                  // Detect delete intent before normal parsing continuation
                  final deleteIntent = await ParserService.instance.parseDeleteIntent(text);
                  if (deleteIntent != null) {
                    List<TransactionModel> txs = [];
                    final mode = deleteIntent['mode'] as String? ?? 'range';
                    if (mode == 'last') {
                      final count = deleteIntent['count'] as int? ?? 1;
                      txs = await DBService.instance.getRecentTransactions(count);
                    } else if (mode == 'range') {
                      final start = deleteIntent['start'] as DateTime? ?? DateTime.fromMillisecondsSinceEpoch(0);
                      final end = deleteIntent['end'] as DateTime? ?? DateTime.now();
                      txs = await DBService.instance.getTransactionsBetween(start, end);
                    } else if (mode == 'all') {
                      txs = await DBService.instance.getTransactionsBetween(DateTime.fromMillisecondsSinceEpoch(0), DateTime.now());
                    }

                    if (txs.isEmpty) {
                      await sendSystemReply('Tidak ada transaksi yang cocok untuk dihapus.', groupId: selectedGroupId.value);
                      controller.clear();
                      return;
                    }

                    // prepare confirmation message
                    final ids = txs.map((t) => t.id).toList();
                    pendingDelete.value = {'ids': ids, 'txs': txs};
                    final sb = StringBuffer();
                    sb.writeln('Perintah penghapusan terdeteksi. Anda akan menghapus ${txs.length} transaksi:');
                    var i = 1;
                    for (final t in txs) {
                      sb.writeln('  ${i++}. ${DateFormat('dd/MM/yyyy').format(t.date)} - ${t.category ?? '-'} - Rp ${nf.format(t.amount)} - ${t.type ?? (t.isIncome ? 'Pendapatan' : 'Pengeluaran')}');
                      if (i > 20) break; // show up to 20
                    }
                    if (txs.length > 20) sb.writeln('  ...dan ${txs.length - 20} transaksi lainnya');
                    sb.writeln('\nBalas dengan "hapus" untuk konfirmasi atau "batal" untuk membatalkan.');

                    await sendSystemReply(sb.toString(), groupId: selectedGroupId.value);
                    controller.clear();
                    return;
                  }

                  // Support batch entry: comma/semicolon separated multiple transactions in one message
                  final parts = text.split(RegExp(r'[,;\n\\/\|]|\bdan\b|\band\b', caseSensitive: false)).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
                  if (parts.length > 1) {
                    final parsedList = <dynamic>[];
                    final failed = <String>[];
                    for (final p in parts) {
                      final pParsed = await ParserService.instance.parseText(p);
                      if (pParsed == null) {
                        failed.add(p);
                        continue;
                      }
                      parsedList.add(pParsed);
                    }

                    if (parsedList.isNotEmpty && failed.isEmpty) {
                       // Insert all parsed transactions
                       final recorded = <String>[];
                       TransactionModel? representativeTx;
                       for (final parsedPart in parsedList) {
                         final descLower = (parsedPart.description ?? '').toLowerCase();
                         final isAssetType = parsedPart.type == 'saving' || parsedPart.type == 'investment';
                         final withdrawalPhrases = ['ambil', 'dari', 'tarik', 'pakai', 'gunakan', 'ambil dari'];
                         final isWithdrawal = isAssetType && withdrawalPhrases.any((p) => descLower.contains(p));

                         if (isWithdrawal) {
                           final assetOutType = '${parsedPart.type}_out';
                           final assetTx = TransactionModel(
                             id: _uuid.v4(),
                             messageId: id,
                             amount: parsedPart.amount,
                             currency: parsedPart.currency ?? 'IDR',
                             category: parsedPart.category ?? (parsedPart.type == 'saving' ? 'Tabungan' : 'Investasi'),
                             description: parsedPart.description,
                             date: parsedPart.date ?? timestamp,
                             createdAt: timestamp,
                             isIncome: false,
                            type: assetOutType,
                            scope: parsedPart.scope ?? 'personal',
                            groupId: selectedGroupId.value,
                           );
                           await DBService.instance.insertTransaction(assetTx);

                           final cashTx = TransactionModel(
                             id: _uuid.v4(),
                             messageId: id,
                             amount: parsedPart.amount,
                             currency: parsedPart.currency ?? 'IDR',
                             category: 'Transfer dari ${parsedPart.type}',
                             description: 'Transfer dari ${parsedPart.type}: ${parsedPart.description}',
                             date: parsedPart.date ?? timestamp,
                             createdAt: timestamp,
                             isIncome: false,
                            type: 'transfer_in',
                            scope: parsedPart.scope ?? 'personal',
                            groupId: selectedGroupId.value,
                           );
                           await DBService.instance.insertTransaction(cashTx);

                           // set representative tx so UI can show parsed info under user message
                           representativeTx ??= assetTx;

                           recorded.add('Penarikan dari ${parsedPart.type}: Rp ${nf.format(parsedPart.amount)}');
                         } else {
                           final tx = TransactionModel(
                             id: _uuid.v4(),
                             messageId: id,
                             amount: parsedPart.amount,
                             currency: parsedPart.currency ?? 'IDR',
                             category: parsedPart.category,
                             description: parsedPart.description,
                             date: parsedPart.date ?? timestamp,
                             createdAt: timestamp,
                             isIncome: parsedPart.isIncome,
                            type: parsedPart.type,
                            scope: parsedPart.scope ?? 'personal',
                            groupId: selectedGroupId.value,
                           );
                           await DBService.instance.insertTransaction(tx);
                           representativeTx ??= tx;
                           final label = parsedPart.type == 'saving'
                               ? 'Tabungan'
                               : parsedPart.type == 'investment'
                                   ? 'Investasi'
                                   : (parsedPart.isIncome ? 'Pendapatan' : 'Pengeluaran');
                           recorded.add('$label: Rp ${nf.format(parsedPart.amount)}');
                         }
                       }

                       // Attach representative transaction to user message (if any)
                       if (representativeTx != null) {
                         try {
                           final idx = messagesState.value.indexWhere((m) => m.id == id);
                           if (idx != -1) {
                             final old = messagesState.value[idx];
                             final updated = Message(id: old.id, text: old.text, createdAt: old.createdAt, parsedTransaction: representativeTx, isSystem: old.isSystem, groupId: old.groupId);
                             final newList = [...messagesState.value];
                             newList[idx] = updated;
                             messagesState.value = newList;
                           }
                         } catch (_) {}
                       }

                       // Totals for current month
                       final monthStart = DateTime(timestamp.year, timestamp.month, 1);
                       final monthEnd = DateTime(timestamp.year, timestamp.month + 1, 1).subtract(const Duration(milliseconds: 1));
                       final totals = await DBService.instance.getTotalsBetween(monthStart, monthEnd);
                       final income = (totals['income'] as num).toDouble();
                       final expense = (totals['expense'] as num).toDouble();
                       final saving = (totals['saving'] as num).toDouble();
                       final investment = (totals['investment'] as num).toDouble();
                       final balance = (totals['balance'] as num).toDouble();

                       final sb = StringBuffer();
                       sb.writeln('Pencatatan batch (${parsedList.length} transaksi):');
                       for (final r in recorded) sb.writeln('  • $r');
                       sb.writeln('- Ringkasan bulan ini:');
                       sb.writeln('  • Pendapatan: Rp ${nf.format(income)}');
                       sb.writeln('  • Pengeluaran: Rp ${nf.format(expense)}');
                       sb.writeln('  • Tabungan: Rp ${nf.format(saving)}');
                       sb.writeln('  • Investasi: Rp ${nf.format(investment)}');
                       sb.writeln('  • Saldo bersih: Rp ${nf.format(balance)}');

                       await sendSystemReply(sb.toString(), groupId: selectedGroupId.value);
                       controller.clear();
                       return;
                    }

                    if (parsedList.isNotEmpty && failed.isNotEmpty) {
                      // Partial success -> ask for confirmation, mark failed parts
                      pendingBatch.value = {'parsed': parsedList, 'failed': failed};
                      final sb = StringBuffer();
                      sb.writeln('Saya berhasil mengenali ${parsedList.length} transaksi, tetapi gagal mengerti bagian berikut:');
                      for (final f in failed) sb.writeln('  • Gagal parse: "$f"');
                      sb.writeln('Jika Anda ingin menyimpan yang berhasil, balas dengan "simpan". Atau perbaiki bagian yang gagal dan kirim ulang.');
                      await sendSystemReply(sb.toString(), groupId: selectedGroupId.value);
                      controller.clear();
                      return;
                    }

                    if (parsedList.isEmpty && failed.isNotEmpty) {
                      // none parsed
                      final sb = StringBuffer();
                      sb.writeln('Maaf, saya tidak bisa memahami format transaksi pada pesan Anda. Coba pisahkan dengan koma atau baris baru, mis: "tabungan sekolah 10000, belanja 5000".');
                      await sendSystemReply(sb.toString(), groupId: selectedGroupId.value);
                      controller.clear();
                      return;
                    }
                    // else: fallthrough
                   }

                  // Detect simple query intents (period parser helper defined here)
                  // re-use 'lower' declared earlier

                  Map<String, dynamic> parsePeriodFromText(String input, DateTime ref) {
                    final months = {
                      'januari': 1, 'jan': 1, 'februari': 2, 'feb': 2, 'maret': 3, 'mar': 3,
                      'april': 4, 'apr': 4, 'mei': 5, 'juni': 6, 'jun': 6, 'juli': 7, 'jul': 7,
                      'agustus': 8, 'agt': 8, 'september': 9, 'sep': 9, 'oktober': 10, 'okt': 10,
                      'november': 11, 'nov': 11, 'desember': 12, 'des': 12,
                      'january': 1, 'february': 2, 'march': 3, 'april': 4, 'may': 5, 'june': 6,
                      'july': 7, 'august': 8, 'september': 9, 'october': 10, 'november': 11, 'december': 12,
                      'jan':1,'feb':2,'mar':3,'apr':4,'jun':6,'jul':7,'aug':8,'sep':9,'oct':10,'nov':11,'dec':12
                    };

                    DateTime start = ref;
                    DateTime end = ref;
                    String label = '';
                    String periodKey = 'all';
                    bool isPeriod = false;
                    bool ambiguous = false;

                    final hasWord = (String w) => input.contains(w);

                    if (hasWord('kemarin') || hasWord('yesterday')) {
                      final day = DateTime(ref.year, ref.month, ref.day).subtract(const Duration(days: 1));
                      start = DateTime(day.year, day.month, day.day);
                      end = start.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
                      label = 'kemarin'; periodKey = 'day'; isPeriod = true;
                      return {'isPeriod': isPeriod, 'ambiguous': false, 'start': start, 'end': end, 'label': label, 'periodKey': periodKey};
                    }

                    if (hasWord('hari ini') || hasWord('today')) {
                      start = DateTime(ref.year, ref.month, ref.day);
                      end = start.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
                      label = 'hari ini'; periodKey = 'day'; isPeriod = true;
                      return {'isPeriod': isPeriod, 'ambiguous': false, 'start': start, 'end': end, 'label': label, 'periodKey': periodKey};
                    }

                    if (hasWord('minggu ini') || hasWord('this week')) {
                      final weekday = ref.weekday;
                      start = DateTime(ref.year, ref.month, ref.day).subtract(Duration(days: weekday - 1));
                      end = start.add(const Duration(days: 7)).subtract(const Duration(milliseconds: 1));
                      label = 'minggu ini'; periodKey = 'week'; isPeriod = true;
                      return {'isPeriod': isPeriod, 'ambiguous': false, 'start': start, 'end': end, 'label': label, 'periodKey': periodKey};
                    }

                    if (hasWord('bulan ini') || hasWord('this month')) {
                      start = DateTime(ref.year, ref.month, 1);
                      end = DateTime(ref.year, ref.month + 1, 1).subtract(const Duration(milliseconds: 1));
                      label = 'bulan ini'; periodKey = 'month'; isPeriod = true;
                      return {'isPeriod': isPeriod, 'ambiguous': false, 'start': start, 'end': end, 'label': label, 'periodKey': periodKey};
                    }

                    // explicit date like '9 agustus 2025'
                    final wordDate = RegExp(r'(\d{1,2})\s+([a-zA-Z]+)\s+(\d{4})');
                    final mWord = wordDate.firstMatch(input);
                    if (mWord != null) {
                      final d = int.tryParse(mWord.group(1) ?? '0') ?? 0;
                      final monthWord = (mWord.group(2) ?? '').toLowerCase();
                      final y = int.tryParse(mWord.group(3) ?? '${ref.year}') ?? ref.year;
                      final m = months[monthWord];
                      if (m != null && d > 0) {
                        start = DateTime(y, m, d);
                        end = start.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
                        label = DateFormat('dd MMM yyyy', 'id').format(start);
                        periodKey = 'day'; isPeriod = true;
                        return {'isPeriod': isPeriod, 'ambiguous': false, 'start': start, 'end': end, 'label': label, 'periodKey': periodKey};
                      }
                    }

                    // month + year e.g. 'juli 2025'
                    final monthYear = RegExp(r'([a-zA-Z]+)\s*(\d{4})');
                    final mMy = monthYear.firstMatch(input);
                    if (mMy != null) {
                      final monthWord = (mMy.group(1) ?? '').toLowerCase();
                      final y = int.tryParse(mMy.group(2) ?? '${ref.year}') ?? ref.year;
                      final m = months[monthWord];
                      if (m != null) {
                        start = DateTime(y, m, 1);
                        end = DateTime(y, m + 1, 1).subtract(const Duration(milliseconds: 1));
                        label = DateFormat('MMMM yyyy', 'id').format(start);
                        periodKey = 'month'; isPeriod = true;
                        return {'isPeriod': isPeriod, 'ambiguous': false, 'start': start, 'end': end, 'label': label, 'periodKey': periodKey};
                      }
                    }

                    // month name only -> ambiguous
                    for (final k in months.keys) {
                      if (input.contains(k) && RegExp(r'\d{4}').firstMatch(input) == null) {
                        final m = months[k]!;
                        start = DateTime(ref.year, m, 1);
                        end = DateTime(ref.year, m + 1, 1).subtract(const Duration(milliseconds: 1));
                        label = DateFormat('MMMM yyyy', 'id').format(start);
                        periodKey = 'month'; isPeriod = true; ambiguous = true;
                        return {'isPeriod': isPeriod, 'ambiguous': ambiguous, 'start': start, 'end': end, 'label': label, 'periodKey': periodKey};
                      }
                    }

                    // numeric date like 09/08 or 09/08/2025
                    final numericDate = RegExp(r'(\d{1,2})[\/\-](\d{1,2})([\/\-](\d{4}))?');
                    final mNum = numericDate.firstMatch(input);
                    if (mNum != null) {
                      final d = int.tryParse(mNum.group(1) ?? '0') ?? 0;
                      final mm = int.tryParse(mNum.group(2) ?? '0') ?? 0;
                      final y = int.tryParse(mNum.group(4) ?? '${ref.year}') ?? ref.year;
                      if (d > 0 && mm > 0) {
                        start = DateTime(y, mm, d);
                        end = start.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
                        label = DateFormat('dd/MM/yyyy').format(start);
                        periodKey = 'day'; isPeriod = true;
                        if (mNum.group(4) == null) ambiguous = true;
                        return {'isPeriod': isPeriod, 'ambiguous': ambiguous, 'start': start, 'end': end, 'label': label, 'periodKey': periodKey};
                      }
                    }

                    // ambiguous keywords
                    if ((input.contains('minggu') && !input.contains('minggu ini') && !input.contains('minggu lalu')) ||
                        (input.contains('bulan') && !input.contains('bulan ini') && !input.contains('bulan lalu')) ||
                        (input.contains('tahun') && !input.contains('tahun ini') && !input.contains('tahun lalu') && !RegExp(r'\d{4}').hasMatch(input))) {
                      ambiguous = true;
                      return {'isPeriod': false, 'ambiguous': ambiguous, 'start': start, 'end': end, 'label': label, 'periodKey': periodKey};
                    }

                    return {'isPeriod': false, 'ambiguous': false, 'start': start, 'end': end, 'label': label, 'periodKey': periodKey};
                  }

                  // Parse period from text (if any)
                  final periodRes = parsePeriodFromText(lower, timestamp);
                   bool isQuery = periodRes['isPeriod'] as bool;
                   DateTime start = periodRes['start'] as DateTime;
                   DateTime end = periodRes['end'] as DateTime;
                   final periodLabelVar = (periodRes['label'] as String?) ?? '';
                   final periodKeyVar = (periodRes['periodKey'] as String?) ?? 'all';
                   final ambiguous = (periodRes['ambiguous'] as bool?) ?? false;

                  if (ambiguous) {
                    // ask for clarification
                    await sendSystemReply('Periode waktu tidak jelas. Maksudnya hari/kemarin/minggu/bulan/tahun tertentu atau tanggal spesifik? Contoh: "ringkasan kemarin", "ringkasan 09 agustus 2025", atau "tabungan juli 2025". (You can reply in English.)', groupId: selectedGroupId.value);
                    controller.clear();
                    return;
                  }

                  final wantsList = lower.contains('daftar') || lower.contains('tampilkan') || lower.contains('catatan') || lower.contains('list') || lower.contains('show');
                  final wantsSummary = lower.contains('ringkasan') || lower.contains('total') || lower.contains('berapa') || lower.contains('pendapatan') || lower.contains('pengeluaran') || lower.contains('tabungan');

                  if (isQuery && wantsSummary && !wantsList) {
                    final totals = await DBService.instance.getTotalsBetween(start, end);
                    final income = (totals['income'] as num).toDouble();
                    final expense = (totals['expense'] as num).toDouble();
                    final saving = (totals['saving'] as num).toDouble();
                    final investment = (totals['investment'] as num).toDouble();
                    final balance = (totals['balance'] as num).toDouble();
                    final count = totals['count'] as int;

                    final periodLabel = (periodLabelVar.isNotEmpty ? periodLabelVar : (lower.contains('hari ini') ? 'hari ini' : lower.contains('minggu') ? 'minggu ini' : lower.contains('bulan') ? 'bulan ini' : 'periode'));
                    final buffer = StringBuffer();
                    buffer.writeln('- Ringkasan ($periodLabel):');
                    buffer.writeln('  • Pendapatan: Rp ${nf.format(income)}');
                    buffer.writeln('  • Pengeluaran: Rp ${nf.format(expense)}');
                    buffer.writeln('  • Tabungan: Rp ${nf.format(saving)}');
                    buffer.writeln('  • Investasi: Rp ${nf.format(investment)}');
                    buffer.writeln('  • Saldo bersih: Rp ${nf.format(balance)}');
                    buffer.writeln('  • Total transaksi: $count');

                    await sendSystemReply(buffer.toString(), groupId: selectedGroupId.value);

                    // If user explicitly asked for tabungan, also show bottom sheet with categories
                    if (lower.contains('tabungan')) {
                      // Instead of bottomsheet, show savings summary directly in chat
                      final rows = await DBService.instance.getSavingsSummaryByPeriod(start: start, end: end, period: periodKeyVar, limit: 100);
                        if (rows.isEmpty) {
                        await sendSystemReply('Tidak ada data tabungan pada periode ini.', groupId: selectedGroupId.value);
                      } else {
                        final sb = StringBuffer();
                        sb.writeln('- Ringkasan Tabungan ($periodLabel):');
                        double totalNet = 0.0;
                        double totalDeposits = 0.0;
                        double totalWithdrawals = 0.0;
                        for (final r in rows) {
                          final cat = (r['category'] as String?) ?? '-';
                          final net = (r['net'] as double?) ?? 0.0;
                          final deposits = (r['deposits'] as double?) ?? 0.0;
                          final withdrawals = (r['withdrawals'] as double?) ?? 0.0;
                          final cnt = (r['count'] as int?) ?? 0;
                          final lastAt = (r['lastAt'] as int?) ?? 0;
                          final lastDt = lastAt > 0 ? DateFormat('dd/MM/yyyy').format(DateTime.fromMillisecondsSinceEpoch(lastAt)) : '-';

                          sb.writeln('  • $cat — Rp ${nf.format(net)} (masuk: Rp ${nf.format(deposits)}, keluar: Rp ${nf.format(withdrawals)}) — $cnt transaksi — terakhir: $lastDt');
                          totalNet += net;
                          totalDeposits += deposits;
                          totalWithdrawals += withdrawals;
                        }
                        sb.writeln('Total tabungan periode: Rp ${nf.format(totalNet)} (masuk: Rp ${nf.format(totalDeposits)}, keluar: Rp ${nf.format(totalWithdrawals)})');
                        await sendSystemReply(sb.toString(), groupId: selectedGroupId.value);
                      }
                    }

                    controller.clear();
                    return;
                  }

                  if (wantsList) {
                    List<TransactionModel> txs = [];
                    if (isQuery) {
                      txs = await DBService.instance.getTransactionsBetween(start, end);
                    } else {
                      txs = await DBService.instance.getRecentTransactions(10);
                    }

                    if (txs.isEmpty) {
                      await sendSystemReply('Tidak ada transaksi ditemukan untuk periode yang diminta.', groupId: selectedGroupId.value);
                    } else {
                      final buffer = StringBuffer();
                      for (final t in txs) {
                        buffer.writeln('${DateFormat('dd/MM').format(t.date)} - ${t.category ?? '-'} - Rp ${nf.format(t.amount)} - ${t.type ?? (t.isIncome ? 'Pendapatan' : 'Pengeluaran')}');
                      }
                      if (!isQuery && txs.length == 10) buffer.writeln('...dan transaksi lainnya.');
                      await sendSystemReply(buffer.toString(), groupId: selectedGroupId.value);
                    }

                    controller.clear();
                    return;
                  }

                  // message already saved above
                  if (parsed != null) {
                    final descLower = (parsed.description ?? '').toLowerCase();
                    final isAssetType = parsed.type == 'saving' || parsed.type == 'investment';
                    final withdrawalPhrases = ['ambil', 'dari', 'tarik', 'pakai', 'gunakan', 'ambil dari'];
                    final isWithdrawal = isAssetType && withdrawalPhrases.any((p) => descLower.contains(p));

                    if (isWithdrawal) {
                      // 1) asset reduction entry (type ends with '_out')
                      final assetOutType = '${parsed.type}_out';
                      final assetTx = TransactionModel(
                        id: _uuid.v4(),
                        messageId: id,
                        amount: parsed.amount,
                        currency: parsed.currency ?? 'IDR',
                        category: parsed.category ?? (parsed.type == 'saving' ? 'Tabungan' : 'Investasi'),
                        description: parsed.description,
                        date: parsed.date ?? timestamp,
                        createdAt: timestamp,
                        isIncome: false,
                        type: assetOutType,
                        scope: parsed.scope ?? 'personal',
                        groupId: selectedGroupId.value,
                      );
                      await DBService.instance.insertTransaction(assetTx);

                      // 2) cash transfer entry (not counted as income)
                      final cashTx = TransactionModel(
                        id: _uuid.v4(),
                        messageId: id,
                        amount: parsed.amount,
                        currency: parsed.currency ?? 'IDR',
                        category: 'Transfer dari ${parsed.type}',
                        description: 'Transfer dari ${parsed.type}: ${parsed.description}',
                        date: parsed.date ?? timestamp,
                        createdAt: timestamp,
                        isIncome: false,
                        type: 'transfer_in',
                        scope: parsed.scope ?? 'personal',
                        groupId: selectedGroupId.value,
                      );
                      await DBService.instance.insertTransaction(cashTx);

                      // Attach representative tx (assetOut) to the user message so UI shows parsed info
                      try {
                        final idx = messagesState.value.indexWhere((m) => m.id == id);
                        if (idx != -1) {
                          final old = messagesState.value[idx];
                          final updated = Message(id: old.id, text: old.text, createdAt: old.createdAt, parsedTransaction: assetTx, isSystem: old.isSystem, groupId: old.groupId);
                          final newList = [...messagesState.value];
                          newList[idx] = updated;
                          messagesState.value = newList;
                        }
                      } catch (_) {}

                      final totals = await DBService.instance.getTotalsBetween(
                        DateTime(timestamp.year, timestamp.month, 1),
                        DateTime(timestamp.year, timestamp.month + 1, 1).subtract(const Duration(milliseconds: 1)),
                      );
                      final income = (totals['income'] as num).toDouble();
                      final expense = (totals['expense'] as num).toDouble();
                      final saving = (totals['saving'] as num).toDouble();
                      final investment = (totals['investment'] as num).toDouble();
                      final balance = (totals['balance'] as num).toDouble();

                      final formatted = StringBuffer();
                      formatted.writeln('Pencatatan: penarikan dari ${parsed.type} — Rp ${nf.format(parsed.amount)}');
                      formatted.writeln('- Ringkasan bulan ini:');
                      formatted.writeln('  • Pendapatan: Rp ${nf.format(income)}');
                      formatted.writeln('  • Pengeluaran: Rp ${nf.format(expense)}');
                      formatted.writeln('  • Tabungan: Rp ${nf.format(saving)}');
                      formatted.writeln('  • Investasi: Rp ${nf.format(investment)}');
                      formatted.writeln('  • Saldo bersih: Rp ${nf.format(balance)}');

                      await sendSystemReply(formatted.toString(), groupId: selectedGroupId.value);
                    } else {
                      // Normal single transaction (expense/income/transfer to saving/investment)
                      final tx = TransactionModel(
                        id: _uuid.v4(),
                        messageId: id,
                        amount: parsed.amount,
                        currency: parsed.currency ?? 'IDR',
                        category: parsed.category,
                        description: parsed.description,
                        date: parsed.date ?? timestamp,
                        createdAt: timestamp,
                        isIncome: parsed.isIncome,
                        type: parsed.type,
                        scope: parsed.scope ?? 'personal',
                        groupId: selectedGroupId.value,
                      );
                      await DBService.instance.insertTransaction(tx);

                      // Attach parsed transaction to the in-memory user message so it shows immediately
                      try {
                        final idx = messagesState.value.indexWhere((m) => m.id == id);
                        if (idx != -1) {
                          final old = messagesState.value[idx];
                          final updated = Message(id: old.id, text: old.text, createdAt: old.createdAt, parsedTransaction: tx, isSystem: old.isSystem, groupId: old.groupId);
                          final newList = [...messagesState.value];
                          newList[idx] = updated;
                          messagesState.value = newList;
                        }
                      } catch (_) {}

                      final monthStart = DateTime(timestamp.year, timestamp.month, 1);
                      final monthEnd = DateTime(timestamp.year, timestamp.month + 1, 1).subtract(const Duration(milliseconds: 1));
                      final totals = await DBService.instance.getTotalsBetween(monthStart, monthEnd);
                      final income = (totals['income'] as num).toDouble();
                      final expense = (totals['expense'] as num).toDouble();
                      final saving = (totals['saving'] as num).toDouble();
                      final investment = (totals['investment'] as num).toDouble();
                      final balance = (totals['balance'] as num).toDouble();

                      final header = parsed.type == 'saving'
                          ? 'Pencatatan tabungan: Rp ${nf.format(parsed.amount)}'
                          : parsed.type == 'investment'
                              ? 'Pencatatan investasi: Rp ${nf.format(parsed.amount)}'
                              : parsed.isIncome
                                  ? 'Pencatatan pendapatan: Rp ${nf.format(parsed.amount)}'
                                  : 'Pencatatan pengeluaran: Rp ${nf.format(parsed.amount)}';

                      final formatted = StringBuffer();
                      formatted.writeln(header);
                      formatted.writeln('- Ringkasan bulan ini:');
                      formatted.writeln('  • Pendapatan: Rp ${nf.format(income)}');
                      formatted.writeln('  • Pengeluaran: Rp ${nf.format(expense)}');
                      formatted.writeln('  • Tabungan: Rp ${nf.format(saving)}');
                      formatted.writeln('  • Investasi: Rp ${nf.format(investment)}');
                      formatted.writeln('  • Saldo bersih: Rp ${nf.format(balance)}');

                      await sendSystemReply(formatted.toString(), tx: tx, groupId: selectedGroupId.value);
                    }
                  } else {
                    // Unknown command / didn't parse as transaction — provide helpful guidance
                    final help = 'Maaf, saya tidak mengerti perintah tersebut. Contoh perintah yang didukung:\n' +
                        '- Catat transaksi: "Beli roti 5000"\n' +
                        '- Lihat ringkasan: "Ringkasan hari ini" / "Ringkasan bulan ini"\n' +
                        '- Lihat daftar: "Tampilkan daftar" atau "Tampilkan daftar hari ini"';
                    await sendSystemReply(help, groupId: selectedGroupId.value);
                  }

                  controller.clear();
                },
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
