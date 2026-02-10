import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:catatan_keuangan_pintar/services/parser_service.dart';
import 'package:catatan_keuangan_pintar/services/db_service.dart';
import 'package:catatan_keuangan_pintar/services/voice_service.dart';
import 'package:catatan_keuangan_pintar/services/ocr_service.dart';
import 'package:catatan_keuangan_pintar/services/auth_service.dart';
import 'package:catatan_keuangan_pintar/services/auto_sync_service.dart';
import 'package:catatan_keuangan_pintar/screens/group_settings.dart';
import 'package:catatan_keuangan_pintar/screens/accept_invite.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatScreen extends HookWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uuid = const Uuid();
    final controller = useTextEditingController();
    final nf = NumberFormat('#,##0', 'id');

    // State
    final messagesState = useState<List<Message>>(<Message>[]);
    final listKey = useRef<GlobalKey<AnimatedListState>>(GlobalKey<AnimatedListState>());
    final scrollController = useScrollController();
    final inputScrollController = useScrollController();
    final pendingBatch = useRef<Map<String, dynamic>?>(null);
    final pendingConfirm = useRef<Map<String, dynamic>?>(null);
    final pendingDelete = useRef<Map<String, dynamic>?>(null);
    final isListening = useState(false);
    final autoConfirmTimer = useRef<Timer?>(null);
    final realtimeChannel = useRef<RealtimeChannel?>(null);
    final groupsState = useState<List<Group>>(<Group>[]);
    final selectedGroupId = useState<String?>(null);

    const prefKeySelectedGroup = 'selectedGroupId';

    // Helper: check if same day
    bool _isSameDay(DateTime a, DateTime b) {
      return a.year == b.year && a.month == b.month && a.day == b.day;
    }

    // Helper: format date separator
    String _formatDateSeparator(DateTime date) {
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));
      
      if (_isSameDay(date, now)) {
        return 'Hari Ini';
      } else if (_isSameDay(date, yesterday)) {
        return 'Kemarin';
      } else {
        return DateFormat('EEEE, dd MMMM yyyy', 'id').format(date);
      }
    }

    // Helper: send system reply
    Future<void> sendSystemReply(String reply, {TransactionModel? tx, String? groupId}) async {
      if (!context.mounted) return;
      
      final sysMsg = Message(
        id: uuid.v4(),
        text: reply,
        createdAt: DateTime.now(),
        parsedTransaction: tx,
        isSystem: true,
        groupId: groupId,
      );
      await DBService.instance.insertMessage(sysMsg);
      
      // Auto-sync to cloud (non-blocking)
      if (groupId != null) {
        AutoSyncService.instance.syncMessage(sysMsg);
      }
      
      messagesState.value = [sysMsg, ...messagesState.value];
      listKey.value.currentState?.insertItem(0, duration: const Duration(milliseconds: 300));
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          if (scrollController.hasClients) {
            scrollController.animateTo(0.0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
          }
        } catch (_) {}
      });
    }

    // Helper: notify group members
    Future<void> notifyGroupMembers(String groupId, String text) async {
      try {
        final rows = await Supabase.instance.client.from('group_members').select('user_id').eq('group_id', groupId);
        if (rows is! List) return;
        
        for (final r in rows) {
          final uid = (r as Map)['user_id']?.toString();
          if (uid == null || uid == AuthService.instance.userId) continue;
          
          await Supabase.instance.client.from('notifications').insert({
            'id': uuid.v4(),
            'user_id': uid,
            'title': 'Pesan baru di grup',
            'body': text.length > 80 ? '${text.substring(0, 80)}...' : text,
            'type': 'chat',
            'data': {'group_id': groupId},
            'created_at': DateTime.now().toIso8601String(),
          });
        }
      } catch (_) {}
    }

    // Helper: subscribe to realtime
    Future<void> subscribeRealtime(String? groupId) async {
      await realtimeChannel.value?.unsubscribe();
      if (groupId == null) return;

      final channel = Supabase.instance.client.channel('messages:$groupId');
      channel.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'group_id',
          value: groupId,
        ),
        callback: (payload) async {
          final data = payload.newRecord;
          final msgId = data['id']?.toString();
          if (msgId == null) return;
          
          final existsIdx = messagesState.value.indexWhere((m) => m.id == msgId);
          if (existsIdx != -1) return;

          final msg = Message(
            id: msgId,
            text: data['text']?.toString() ?? '',
            createdAt: DateTime.tryParse(data['created_at']?.toString() ?? '') ?? DateTime.now(),
            parsedTransaction: null,
            isSystem: data['is_system'] == true,
            groupId: groupId,
          );
          
          await DBService.instance.insertMessage(msg);
          messagesState.value = [msg, ...messagesState.value];
          listKey.value.currentState?.insertItem(0, duration: const Duration(milliseconds: 300));
        },
      );
      
      channel.subscribe();
      realtimeChannel.value = channel;
    }

    // Helper: determine scope based on selected group
    String _currentScope() {
      return selectedGroupId.value != null ? 'group' : 'personal';
    }

    // Helper: save parsed transaction
    Future<void> saveParsed(ParsedTransaction parsedPart, String messageId, DateTime timestamp) async {
      final descLower = (parsedPart.description ?? '').toLowerCase();
      final isAssetType = parsedPart.type == 'saving' || parsedPart.type == 'investment';
      final withdrawalPhrases = ['ambil', 'dari', 'tarik', 'pakai', 'gunakan', 'ambil dari'];
      final isWithdrawal = isAssetType && withdrawalPhrases.any((p) => descLower.contains(p));
      final scope = _currentScope();

      if (isWithdrawal) {
        final assetOutType = '${parsedPart.type}_out';
        final assetTx = TransactionModel(
          id: uuid.v4(),
          messageId: messageId,
          amount: parsedPart.amount,
          currency: parsedPart.currency ?? 'IDR',
          category: parsedPart.category ?? (parsedPart.type == 'saving' ? 'Tabungan' : 'Investasi'),
          description: parsedPart.description,
          date: parsedPart.date ?? timestamp,
          createdAt: timestamp,
          isIncome: false,
          type: assetOutType,
          scope: scope,
          groupId: selectedGroupId.value,
        );
        await DBService.instance.insertTransaction(assetTx);
        // Auto-sync to cloud
        AutoSyncService.instance.syncTransaction(assetTx);

        final cashTx = TransactionModel(
          id: uuid.v4(),
          messageId: messageId,
          amount: parsedPart.amount,
          currency: parsedPart.currency ?? 'IDR',
          category: 'Transfer dari ${parsedPart.type}',
          description: 'Transfer dari ${parsedPart.type}: ${parsedPart.description}',
          date: parsedPart.date ?? timestamp,
          createdAt: timestamp,
          isIncome: false,
          type: 'transfer_in',
          scope: scope,
          groupId: selectedGroupId.value,
        );
        await DBService.instance.insertTransaction(cashTx);
        // Auto-sync to cloud
        AutoSyncService.instance.syncTransaction(cashTx);
      } else {
        final tx = TransactionModel(
          id: uuid.v4(),
          messageId: messageId,
          amount: parsedPart.amount,
          currency: parsedPart.currency ?? 'IDR',
          category: parsedPart.category,
          description: parsedPart.description,
          date: parsedPart.date ?? timestamp,
          createdAt: timestamp,
          isIncome: parsedPart.isIncome,
          type: parsedPart.type,
          scope: scope,
          groupId: selectedGroupId.value,
        );
        await DBService.instance.insertTransaction(tx);
        // Auto-sync to cloud
        AutoSyncService.instance.syncTransaction(tx);
      }
    }

    // Helper: prompt confirmation for voice/OCR
    Future<void> promptConfirm(ParsedTransaction parsedPart, {required String source, bool autoSave = false}) async {
      if (!context.mounted) return;
      
      final label = parsedPart.type == 'saving'
          ? 'Tabungan'
          : parsedPart.type == 'investment'
              ? 'Investasi'
              : (parsedPart.isIncome ? 'Pendapatan' : 'Pengeluaran');
      final dateLabel = parsedPart.date != null ? DateFormat('dd MMM yyyy', 'id').format(parsedPart.date!) : 'hari ini';
      final catLabel = parsedPart.category ?? '-';
      
      // Check if account is mentioned
      String accountInfo = '';
      if (parsedPart.accountId != null || parsedPart.accountName != null) {
        final accName = parsedPart.accountName ?? 'Unknown';
        accountInfo = '\n- Sumber Dana: $accName';
      } else {
        accountInfo = '\n- Sumber Dana: (tidak disebutkan)';
      }
      
      pendingConfirm.value = {'parsed': parsedPart, 'source': source};
      autoConfirmTimer.value?.cancel();
      
      await sendSystemReply(
        'Saya tangkap:\n'
        '- Tipe: $label\n'
        '- Nominal: Rp ${nf.format(parsedPart.amount)}\n'
        '- Kategori: $catLabel\n'
        '- Tanggal: $dateLabel'
        '$accountInfo\n'
        'Ketik "ya" untuk simpan, "edit" untuk ubah, atau "batal".'
        '${autoSave ? '\nJika tidak ada respon dalam 5 detik, transaksi akan disimpan otomatis.' : ''}',
        groupId: selectedGroupId.value,
      );
      
      if (autoSave) {
        final msgId = uuid.v4();
        final ts = DateTime.now();
        autoConfirmTimer.value = Timer(const Duration(seconds: 5), () async {
          if (pendingConfirm.value != null && pendingConfirm.value!['source'] == source) {
            final p = pendingConfirm.value!['parsed'] as ParsedTransaction;
            await saveParsed(p, msgId, ts);
            pendingConfirm.value = null;
            final label = source == 'voice' ? 'Voice' : source == 'ocr' ? 'OCR' : 'Chat';
            await sendSystemReply('Transaksi $label disimpan otomatis karena tidak ada konfirmasi dalam 5 detik.', groupId: selectedGroupId.value);
          }
        });
      }
    }

    // Helper: batch summary
    String batchSummary(List<ParsedTransaction> list) {
      final sb = StringBuffer();
      sb.writeln('Saya tangkap ${list.length} transaksi:');
      var i = 1;
      for (final p in list) {
        final label = p.type == 'saving'
            ? 'Tabungan'
            : p.type == 'investment'
                ? 'Investasi'
                : (p.isIncome ? 'Pendapatan' : 'Pengeluaran');
        final dateLabel = p.date != null ? DateFormat('dd MMM yyyy', 'id').format(p.date!) : 'hari ini';
        sb.writeln('  ${i++}. $label - Rp ${nf.format(p.amount)} - ${p.category ?? '-'} - $dateLabel');
      }
      sb.writeln('Ketik "simpan" untuk menyimpan semuanya, "edit N" untuk ubah item ke-N, atau "batal".');
      return sb.toString();
    }

    // Helper: show edit dialog
    Future<ParsedTransaction?> showEditDialog(ParsedTransaction parsedPart) async {
      if (!context.mounted) return null;
      
      final amountCtrl = TextEditingController(text: parsedPart.amount.toStringAsFixed(0));
      final categoryCtrl = TextEditingController(text: parsedPart.category ?? '');
      final dateCtrl = TextEditingController(
        text: parsedPart.date != null ? DateFormat('dd/MM/yyyy').format(parsedPart.date!) : '',
      );
      String txTypeValue = parsedPart.type;

      final result = await showDialog<ParsedTransaction?>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('Edit Transaksi'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: txTypeValue,
                  decoration: const InputDecoration(labelText: 'Tipe'),
                  items: const [
                    DropdownMenuItem(value: 'expense', child: Text('Pengeluaran')),
                    DropdownMenuItem(value: 'income', child: Text('Pendapatan')),
                    DropdownMenuItem(value: 'saving', child: Text('Tabungan')),
                    DropdownMenuItem(value: 'investment', child: Text('Investasi')),
                  ],
                  onChanged: (v) => setStateDialog(() => txTypeValue = v ?? 'expense'),
                ),
                TextField(controller: amountCtrl, decoration: const InputDecoration(labelText: 'Nominal'), keyboardType: TextInputType.number),
                TextField(controller: categoryCtrl, decoration: const InputDecoration(labelText: 'Kategori')),
                TextField(controller: dateCtrl, decoration: const InputDecoration(labelText: 'Tanggal (dd/MM/yyyy)')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () {
                final editedAmount = double.tryParse(amountCtrl.text.replaceAll('.', '').replaceAll(',', '')) ?? parsedPart.amount;
                DateTime? editedDate;
                if (dateCtrl.text.trim().isNotEmpty) {
                  final parts = dateCtrl.text.trim().split('/');
                  if (parts.length == 3) {
                    final d = int.tryParse(parts[0]) ?? 0;
                    final m = int.tryParse(parts[1]) ?? 0;
                    final y = int.tryParse(parts[2]) ?? DateTime.now().year;
                    if (d > 0 && m > 0) editedDate = DateTime(y, m, d);
                  }
                }
                
                final edited = ParsedTransaction(
                  amount: editedAmount,
                  currency: parsedPart.currency,
                  category: categoryCtrl.text.trim().isEmpty ? parsedPart.category : categoryCtrl.text.trim(),
                  description: parsedPart.description,
                  date: editedDate ?? parsedPart.date,
                  isIncome: txTypeValue == 'income',
                  type: txTypeValue,
                  scope: parsedPart.scope,
                );
                Navigator.of(ctx).pop(edited);
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
        ),
      );
      return result;
    }

    // Send message logic
    Future<void> sendMessage(String text) async {
      if (text.isEmpty) return;

      final id = uuid.v4();
      final timestamp = DateTime.now();
      
      final userMsg = Message(
        id: id,
        text: text,
        createdAt: timestamp,
        parsedTransaction: null,
        isSystem: false,
        groupId: selectedGroupId.value,
      );
      
      await DBService.instance.insertMessage(userMsg);
      
      // Auto-sync to cloud (non-blocking)
      if (selectedGroupId.value != null) {
        AutoSyncService.instance.syncMessage(userMsg);
        await notifyGroupMembers(selectedGroupId.value!, text);
      }
      
      messagesState.value = [userMsg, ...messagesState.value];
      listKey.value.currentState?.insertItem(0, duration: const Duration(milliseconds: 300));

      // Handle pending confirmation
      if (pendingConfirm.value != null) {
        final textLower = text.toLowerCase();
        final p = pendingConfirm.value!['parsed'] as ParsedTransaction;
        
        if (textLower.contains('ya') || textLower.contains('ok') || textLower.contains('oke')) {
          autoConfirmTimer.value?.cancel();
          await saveParsed(p, uuid.v4(), DateTime.now());
          pendingConfirm.value = null;
          
          final monthStart = DateTime(timestamp.year, timestamp.month, 1);
          final monthEnd = DateTime(timestamp.year, timestamp.month + 1, 1).subtract(const Duration(milliseconds: 1));
          final totals = await DBService.instance.getTotalsBetween(monthStart, monthEnd, groupId: selectedGroupId.value);
          
          final income = (totals['income'] as num).toDouble();
          final expense = (totals['expense'] as num).toDouble();
          final saving = (totals['saving'] as num).toDouble();
          final investment = (totals['investment'] as num).toDouble();
          final balance = (totals['balance'] as num).toDouble();

          final formatted = StringBuffer();
          formatted.writeln('Pencatatan (1 transaksi) berhasil:');
          formatted.writeln('- Ringkasan bulan ini:');
          formatted.writeln('  • Pendapatan: Rp ${nf.format(income)}');
          formatted.writeln('  • Pengeluaran: Rp ${nf.format(expense)}');
          formatted.writeln('  • Tabungan: Rp ${nf.format(saving)}');
          formatted.writeln('  • Investasi: Rp ${nf.format(investment)}');
          formatted.writeln('  • Saldo bersih: Rp ${nf.format(balance)}');

          await sendSystemReply(formatted.toString(), groupId: selectedGroupId.value);
          return;
        } else if (textLower.contains('edit')) {
          autoConfirmTimer.value?.cancel();
          final edited = await showEditDialog(p);
          if (edited != null) {
            pendingConfirm.value = {'parsed': edited, 'source': pendingConfirm.value!['source']};
            await promptConfirm(edited, source: pendingConfirm.value!['source'] as String, autoSave: false);
          }
          return;
        } else if (textLower.contains('batal')) {
          autoConfirmTimer.value?.cancel();
          pendingConfirm.value = null;
          await sendSystemReply('Transaksi dibatalkan.', groupId: selectedGroupId.value);
          return;
        }
      }

      // Handle pending batch
      if (pendingBatch.value != null) {
        final textLower = text.toLowerCase();
        final batch = pendingBatch.value!['batch'] as List<ParsedTransaction>;
        
        if (textLower.contains('simpan')) {
          for (final p in batch) {
            await saveParsed(p, uuid.v4(), DateTime.now());
          }
          pendingBatch.value = null;
          await sendSystemReply('${batch.length} transaksi berhasil disimpan.', groupId: selectedGroupId.value);
          return;
        } else if (textLower.startsWith('edit ')) {
          final numStr = textLower.replaceFirst('edit ', '').trim();
          final num = int.tryParse(numStr);
          if (num != null && num > 0 && num <= batch.length) {
            final edited = await showEditDialog(batch[num - 1]);
            if (edited != null) {
              final newBatch = [...batch];
              newBatch[num - 1] = edited;
              pendingBatch.value = {'batch': newBatch};
              await sendSystemReply(batchSummary(newBatch), groupId: selectedGroupId.value);
            }
          }
          return;
        } else if (textLower.contains('batal')) {
          pendingBatch.value = null;
          await sendSystemReply('Batch transaksi dibatalkan.', groupId: selectedGroupId.value);
          return;
        }
      }

      // Handle pending delete confirmation
      if (pendingDelete.value != null) {
        final textLower = text.toLowerCase();
        final confirmWords = ['hapus', 'ya', 'konfirmasi', 'confirm', 'ok', 'oke'];
        final cancelWords = ['batal', 'cancel', 'tidak', 'no'];
        
        if (confirmWords.any((w) => textLower == w || textLower.contains(w))) {
          final ids = (pendingDelete.value!['ids'] as List<String>?) ?? <String>[];
          if (ids.isEmpty) {
            await sendSystemReply('Tidak ada transaksi untuk dihapus.', groupId: selectedGroupId.value);
            pendingDelete.value = null;
            return;
          }

          await DBService.instance.deleteTransactionsSoft(ids);

          // Auto-sync deletions to cloud
          for (final id in ids) {
            // Sync will handle soft-delete flag automatically
          }

          final monthStart = DateTime(timestamp.year, timestamp.month, 1);
          final monthEnd = DateTime(timestamp.year, timestamp.month + 1, 1).subtract(const Duration(milliseconds: 1));
          final totals = await DBService.instance.getTotalsBetween(monthStart, monthEnd, groupId: selectedGroupId.value);
          final income = (totals['income'] as num).toDouble();
          final expense = (totals['expense'] as num).toDouble();
          final saving = (totals['saving'] as num).toDouble();
          final investment = (totals['investment'] as num).toDouble();
          final balance = (totals['balance'] as num).toDouble();

          final sb = StringBuffer();
          sb.writeln('✅ Berhasil menghapus ${ids.length} transaksi (soft-delete).');
          sb.writeln('');
          sb.writeln('📊 Ringkasan bulan ini setelah penghapusan:');
          sb.writeln('  • Pendapatan: Rp ${nf.format(income)}');
          sb.writeln('  • Pengeluaran: Rp ${nf.format(expense)}');
          sb.writeln('  • Tabungan: Rp ${nf.format(saving)}');
          sb.writeln('  • Investasi: Rp ${nf.format(investment)}');
          sb.writeln('  • Saldo bersih: Rp ${nf.format(balance)}');

          pendingDelete.value = null;
          await sendSystemReply(sb.toString(), groupId: selectedGroupId.value);
          return;
        }

        if (cancelWords.any((w) => textLower == w || textLower.contains(w))) {
          pendingDelete.value = null;
          await sendSystemReply('❌ Perintah penghapusan dibatalkan. Tidak ada data yang dihapus.', groupId: selectedGroupId.value);
          return;
        }
      }

      // Parse as normal message using parseIntent to handle batch transactions and delete commands
      final intent = await ParserService.instance.parseIntent(text);
      
      // Handle delete intent
      if (intent != null && intent['intent'] == 'delete') {
        final deleteSpec = intent['delete'] ?? intent['deleteSpec'] ?? <String, dynamic>{};
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
          txs = await DBService.instance.getTransactionsBetween(
            DateTime.fromMillisecondsSinceEpoch(0),
            DateTime.now(),
          );
        }

        if (txs.isEmpty) {
          await sendSystemReply(
            '❌ Tidak ada transaksi yang cocok untuk dihapus.',
            groupId: selectedGroupId.value,
          );
          return;
        }

        // Prepare confirmation message
        final ids = txs.map((t) => t.id).toList();
        pendingDelete.value = {'ids': ids, 'txs': txs};
        
        final sb = StringBuffer();
        sb.writeln('⚠️ Perintah penghapusan terdeteksi!');
        sb.writeln('\nAnda akan menghapus ${txs.length} transaksi:');
        sb.writeln('');
        
        var i = 1;
        for (final t in txs) {
          final typeLabel = t.type ?? (t.isIncome ? 'Pendapatan' : 'Pengeluaran');
          sb.writeln(
            '  ${i++}. ${DateFormat('dd/MM/yyyy').format(t.date)} - '
            '${t.category ?? '-'} - '
            'Rp ${nf.format(t.amount)} - '
            '$typeLabel'
          );
          if (i > 20) break; // show max 20 transactions
        }
        
        if (txs.length > 20) {
          sb.writeln('  ...dan ${txs.length - 20} transaksi lainnya');
        }
        
        sb.writeln('');
        sb.writeln('Balas dengan "hapus" atau "ya" untuk konfirmasi,');
        sb.writeln('atau "batal" untuk membatalkan.');

        await sendSystemReply(sb.toString(), groupId: selectedGroupId.value);
        return;
      }
      
      // Handle summary/list query intents
      if (intent != null && (intent['intent'] == 'summary' || intent['intent'] == 'list')) {
        final period = intent['period'] as Map<String, dynamic>?;
        DateTime start;
        DateTime end;
        String periodLabel = '';

        if (period != null && period['start'] != null && period['end'] != null) {
          start = period['start'] as DateTime;
          end = period['end'] as DateTime;
          periodLabel = (period['label'] as String?) ?? '';
        } else {
          // default to current month
          final now = DateTime.now();
          start = DateTime(now.year, now.month, 1);
          end = DateTime(now.year, now.month + 1, 1).subtract(const Duration(milliseconds: 1));
          periodLabel = 'bulan ini';
        }

        if (intent['intent'] == 'summary') {
          final totals = await DBService.instance.getTotalsBetween(start, end, groupId: selectedGroupId.value);
          final income = (totals['income'] as num).toDouble();
          final expense = (totals['expense'] as num).toDouble();
          final saving = (totals['saving'] as num).toDouble();
          final investment = (totals['investment'] as num).toDouble();
          final balance = (totals['balance'] as num).toDouble();
          final count = totals['count'] as int;

          final buffer = StringBuffer();
          buffer.writeln('📊 Ringkasan ${periodLabel.isNotEmpty ? periodLabel : 'periode'}:');
          buffer.writeln('');
          buffer.writeln('  💰 Pendapatan: Rp ${nf.format(income)}');
          buffer.writeln('  💸 Pengeluaran: Rp ${nf.format(expense)}');
          buffer.writeln('  🏦 Tabungan: Rp ${nf.format(saving)}');
          buffer.writeln('  📈 Investasi: Rp ${nf.format(investment)}');
          buffer.writeln('  💵 Saldo bersih: Rp ${nf.format(balance)}');
          buffer.writeln('  📝 Total transaksi: $count');

          await sendSystemReply(buffer.toString(), groupId: selectedGroupId.value);

          // If user asked for savings specifically, show detailed breakdown
          if (text.toLowerCase().contains('tabungan') || text.toLowerCase().contains('saving')) {
            final periodKey = (period?['periodKey'] as String?) ?? 'all';
            final rows = await DBService.instance.getSavingsSummaryByPeriod(
              start: start,
              end: end,
              period: periodKey,
              limit: 100,
            );
            
            if (rows.isNotEmpty) {
              final sb = StringBuffer();
              sb.writeln('');
              sb.writeln('💎 Detail Tabungan per Kategori:');
              sb.writeln('');
              
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
                final lastDt = lastAt > 0 
                    ? DateFormat('dd/MM/yyyy').format(DateTime.fromMillisecondsSinceEpoch(lastAt))
                    : '-';

                sb.writeln('  • $cat');
                sb.writeln('    Saldo: Rp ${nf.format(net)}');
                sb.writeln('    Masuk: Rp ${nf.format(deposits)} | Keluar: Rp ${nf.format(withdrawals)}');
                sb.writeln('    $cnt transaksi | Terakhir: $lastDt');
                sb.writeln('');
                
                totalNet += net;
                totalDeposits += deposits;
                totalWithdrawals += withdrawals;
              }
              
              sb.writeln('─────────────────');
              sb.writeln('Total: Rp ${nf.format(totalNet)}');
              sb.writeln('Masuk: Rp ${nf.format(totalDeposits)} | Keluar: Rp ${nf.format(totalWithdrawals)}');
              
              await sendSystemReply(sb.toString(), groupId: selectedGroupId.value);
            }
          }
          return;
        }

        if (intent['intent'] == 'list') {
          List<TransactionModel> txs = [];
          final periodProvided = period != null && period['start'] != null && period['end'] != null;
          
          if (periodProvided) {
            txs = await DBService.instance.getTransactionsBetween(start, end);
          } else {
            final count = (intent['count'] as int?) ?? 10;
            txs = await DBService.instance.getRecentTransactions(count);
          }

          if (txs.isEmpty) {
            await sendSystemReply(
              '📋 Tidak ada transaksi ditemukan untuk periode yang diminta.',
              groupId: selectedGroupId.value,
            );
          } else {
            final buffer = StringBuffer();
            buffer.writeln('📋 Daftar Transaksi ${periodLabel.isNotEmpty ? '($periodLabel)' : ''}:');
            buffer.writeln('');
            
            for (final t in txs) {
              final dateStr = DateFormat('dd/MM').format(t.date);
              final typeLabel = t.type ?? (t.isIncome ? 'Pendapatan' : 'Pengeluaran');
              final icon = t.isIncome ? '💰' : '💸';
              
              buffer.writeln('$icon $dateStr - ${t.category ?? '-'}');
              buffer.writeln('   Rp ${nf.format(t.amount)} - $typeLabel');
            }
            
            if (!periodProvided && txs.length == ((intent['count'] as int?) ?? 10)) {
              buffer.writeln('');
              buffer.writeln('...dan transaksi lainnya');
            }
            
            await sendSystemReply(buffer.toString(), groupId: selectedGroupId.value);
          }
          return;
        }
      }
      
      if (intent != null && intent['intent'] == 'create') {
        final transactions = (intent['transactions'] as List?)?.cast<ParsedTransaction>() ?? [];
        
        if (transactions.isEmpty) {
          // No valid transactions parsed
          final help = 'Maaf, saya tidak mengerti perintah tersebut. Contoh perintah yang didukung:\n'
              '- Catat transaksi: "Beli roti 5000"\n'
              '- Batch: "Beli bakso 5rb, sayur 5rb, jajan 10rb"\n'
              '- Lihat ringkasan: "Ringkasan hari ini"';
          await sendSystemReply(help, groupId: selectedGroupId.value);
          return;
        }
        
        if (transactions.length > 1) {
          // Batch transactions - prompt for confirmation
          pendingBatch.value = {'batch': transactions};
          await sendSystemReply(batchSummary(transactions), groupId: selectedGroupId.value);
          return;
        }
        
        // Single transaction - auto save
        final parsed = transactions[0];
        final descLower = (parsed.description ?? '').toLowerCase();
        final isAssetType = parsed.type == 'saving' || parsed.type == 'investment';
        final withdrawalPhrases = ['ambil', 'dari', 'tarik', 'pakai', 'gunakan', 'ambil dari'];
        final isWithdrawal = isAssetType && withdrawalPhrases.any((p) => descLower.contains(p));

        if (isWithdrawal) {
          final assetOutType = '${parsed.type}_out';
          final assetTx = TransactionModel(
            id: uuid.v4(),
            messageId: id,
            amount: parsed.amount,
            currency: parsed.currency ?? 'IDR',
            category: parsed.category ?? (parsed.type == 'saving' ? 'Tabungan' : 'Investasi'),
            description: parsed.description,
            date: parsed.date ?? timestamp,
            createdAt: timestamp,
            isIncome: false,
            type: assetOutType,
            scope: _currentScope(),
            groupId: selectedGroupId.value,
          );
          await DBService.instance.insertTransaction(assetTx);
          // Auto-sync
          AutoSyncService.instance.syncTransaction(assetTx);

          final cashTx = TransactionModel(
            id: uuid.v4(),
            messageId: id,
            amount: parsed.amount,
            currency: parsed.currency ?? 'IDR',
            category: 'Transfer dari ${parsed.type}',
            description: 'Transfer dari ${parsed.type}: ${parsed.description}',
            date: parsed.date ?? timestamp,
            createdAt: timestamp,
            isIncome: false,
            type: 'transfer_in',
            scope: _currentScope(),
            groupId: selectedGroupId.value,
          );
          await DBService.instance.insertTransaction(cashTx);
          // Auto-sync
          AutoSyncService.instance.syncTransaction(cashTx);

          try {
            final idx = messagesState.value.indexWhere((m) => m.id == id);
            if (idx != -1) {
              final old = messagesState.value[idx];
              final updated = Message(
                id: old.id,
                text: old.text,
                createdAt: old.createdAt,
                parsedTransaction: assetTx,
                isSystem: old.isSystem,
                groupId: old.groupId,
              );
              final newList = [...messagesState.value];
              newList[idx] = updated;
              messagesState.value = newList;
            }
          } catch (_) {}

          final totals = await DBService.instance.getTotalsBetween(
            DateTime(timestamp.year, timestamp.month, 1),
            DateTime(timestamp.year, timestamp.month + 1, 1).subtract(const Duration(milliseconds: 1)),
            groupId: selectedGroupId.value,
          );
          
          final income = (totals['income'] as num).toDouble();
          final expense = (totals['expense'] as num).toDouble();
          final saving = (totals['saving'] as num).toDouble();
          final investment = (totals['investment'] as num).toDouble();
          final balance = (totals['balance'] as num).toDouble();

          final formatted = StringBuffer();
          formatted.writeln('Pencatatan (1 transaksi) berhasil:');
          formatted.writeln('- Ringkasan bulan ini:');
          formatted.writeln('  • Pendapatan: Rp ${nf.format(income)}');
          formatted.writeln('  • Pengeluaran: Rp ${nf.format(expense)}');
          formatted.writeln('  • Tabungan: Rp ${nf.format(saving)}');
          formatted.writeln('  • Investasi: Rp ${nf.format(investment)}');
          formatted.writeln('  • Saldo bersih: Rp ${nf.format(balance)}');

          await sendSystemReply(formatted.toString(), groupId: selectedGroupId.value);
        } else {
          final tx = TransactionModel(
            id: uuid.v4(),
            messageId: id,
            amount: parsed.amount,
            currency: parsed.currency ?? 'IDR',
            category: parsed.category,
            description: parsed.description,
            date: parsed.date ?? timestamp,
            createdAt: timestamp,
            isIncome: parsed.isIncome,
            type: parsed.type,
            scope: _currentScope(),
            groupId: selectedGroupId.value,
          );
          await DBService.instance.insertTransaction(tx);
          // Auto-sync
          AutoSyncService.instance.syncTransaction(tx);

          try {
            final idx = messagesState.value.indexWhere((m) => m.id == id);
            if (idx != -1) {
              final old = messagesState.value[idx];
              final updated = Message(
                id: old.id,
                text: old.text,
                createdAt: old.createdAt,
                parsedTransaction: tx,
                isSystem: old.isSystem,
                groupId: old.groupId,
              );
              final newList = [...messagesState.value];
              newList[idx] = updated;
              messagesState.value = newList;
            }
          } catch (_) {}

          final monthStart = DateTime(timestamp.year, timestamp.month, 1);
          final monthEnd = DateTime(timestamp.year, timestamp.month + 1, 1).subtract(const Duration(milliseconds: 1));
          final totals = await DBService.instance.getTotalsBetween(monthStart, monthEnd, groupId: selectedGroupId.value);
          
          final income = (totals['income'] as num).toDouble();
          final expense = (totals['expense'] as num).toDouble();
          final saving = (totals['saving'] as num).toDouble();
          final investment = (totals['investment'] as num).toDouble();
          final balance = (totals['balance'] as num).toDouble();

          final formatted = StringBuffer();
          formatted.writeln('Pencatatan (1 transaksi) berhasil:');
          formatted.writeln('- Ringkasan bulan ini:');
          formatted.writeln('  • Pendapatan: Rp ${nf.format(income)}');
          formatted.writeln('  • Pengeluaran: Rp ${nf.format(expense)}');
          formatted.writeln('  • Tabungan: Rp ${nf.format(saving)}');
          formatted.writeln('  • Investasi: Rp ${nf.format(investment)}');
          formatted.writeln('  • Saldo bersih: Rp ${nf.format(balance)}');

          await sendSystemReply(formatted.toString(), tx: tx, groupId: selectedGroupId.value);
        }
      } else {
        // Not a transaction or delete command, provide comprehensive help
        final help = '❓ Maaf, saya tidak mengerti perintah tersebut.\n\n'
            '📝 Contoh perintah yang didukung:\n\n'
            '💰 Catat Transaksi:\n'
            '  • "Beli roti 5000"\n'
            '  • "Beli bakso 5rb, sayur 5rb, jajan 10rb" (batch)\n'
            '  • "Terima gaji 5juta"\n'
            '  • "Tabung dana darurat 500rb"\n\n'
            '🗑️ Hapus Transaksi:\n'
            '  • "Hapus transaksi terakhir"\n'
            '  • "Hapus 3 transaksi terakhir"\n'
            '  • "Hapus transaksi kemarin"\n'
            '  • "Hapus transaksi 09/01/2026"\n'
            '  • "Hapus transaksi hari ini"\n\n'
            '📊 Lihat Ringkasan:\n'
            '  • "Ringkasan hari ini"\n'
            '  • "Ringkasan kemarin"\n'
            '  • "Ringkasan minggu ini"\n'
            '  • "Ringkasan bulan ini"\n'
            '  • "Ringkasan 09 Agustus 2025"\n'
            '  • "Tabungan Juli 2025" (detail per kategori)\n\n'
            '📋 Lihat Daftar:\n'
            '  • "Daftar transaksi"\n'
            '  • "Daftar transaksi hari ini"\n'
            '  • "Tampilkan 20 transaksi terakhir"';
        await sendSystemReply(help, groupId: selectedGroupId.value);
      }
    }

    // Initialize
    useEffect(() {
      Future<void> init() async {
        final prefs = await SharedPreferences.getInstance();
        final savedGroupId = prefs.getString(prefKeySelectedGroup);
        
        final gs = await DBService.instance.getGroups();
        groupsState.value = gs;
        
        if (savedGroupId != null && gs.any((g) => g.id == savedGroupId)) {
          selectedGroupId.value = savedGroupId;
        }
        
        final list = await DBService.instance.getMessagesForGroup(selectedGroupId.value);
        messagesState.value = list.reversed.toList();
        
        await subscribeRealtime(selectedGroupId.value);
      }
      
      init();
      
      return () {
        realtimeChannel.value?.unsubscribe();
        autoConfirmTimer.value?.cancel();
      };
    }, []);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat Keuangan'),
        actions: [
          // Network & Sync Status Indicator
          StreamBuilder<bool>(
            stream: Stream.periodic(const Duration(seconds: 1), (_) => AutoSyncService.instance.isOnline),
            initialData: AutoSyncService.instance.isOnline,
            builder: (context, snapshot) {
              final isOnline = snapshot.data ?? false;
              final pendingCount = AutoSyncService.instance.pendingSyncCount;
              
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Network status icon
                  Icon(
                    isOnline ? Icons.cloud_done : Icons.cloud_off,
                    color: isOnline ? Colors.green : Colors.orange,
                    size: 20,
                  ),
                  
                  // Pending count badge
                  if (pendingCount > 0)
                    Container(
                      margin: const EdgeInsets.only(left: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$pendingCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  
                  // Manual sync button
                  IconButton(
                    icon: const Icon(Icons.sync, size: 20),
                    tooltip: 'Sinkronisasi manual',
                    onPressed: AutoSyncService.instance.isSyncing
                        ? null
                        : () async {
                            await AutoSyncService.instance.syncNow();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Sinkronisasi selesai'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                  ),
                ],
              );
            },
          ),
          
          if (selectedGroupId.value != null)
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () async {
                final deleted = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => GroupSettingsScreen(
                      groupId: selectedGroupId.value!,
                      currentUserId: AuthService.instance.userId,
                    ),
                  ),
                );
                if (deleted == true) {
                  final gs2 = await DBService.instance.getGroups();
                  groupsState.value = gs2;
                  selectedGroupId.value = null;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove(prefKeySelectedGroup);
                  final list = await DBService.instance.getMessagesForGroup(null);
                  messagesState.value = list.reversed.toList();
                  await subscribeRealtime(null);
                }
              },
            ),
        ],
      ),
      body: Column(
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
                              
                              final id = uuid.v4();
                              final g = Group(
                                id: id,
                                name: name,
                                description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                                icon: null,
                                createdAt: DateTime.now(),
                                createdBy: AuthService.instance.userId,
                              );
                              
                              await DBService.instance.insertGroup(g);
                              final member = GroupMember(
                                id: 'gm_${id}_${AuthService.instance.userId}',
                                groupId: id,
                                userId: AuthService.instance.userId,
                                role: 'owner',
                                status: 'accepted',
                                joinedAt: DateTime.now(),
                              );
                              await DBService.instance.insertGroupMember(member);
                              final gs2 = await DBService.instance.getGroups();
                              groupsState.value = gs2;
                              selectedGroupId.value = id;
                              
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setString(prefKeySelectedGroup, id);
                              
                              final list2 = await DBService.instance.getMessagesForGroup(id);
                              messagesState.value = list2.reversed.toList();
                              
                              await subscribeRealtime(id);
                              
                              if (ctx.mounted) {
                                Navigator.of(ctx).pop(true);
                              }
                            },
                            child: const Text('Buat'),
                          ),
                        ],
                      ),
                    );
                    
                    if (res == true) {
                      // Group created and selected
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.input),
                  tooltip: 'Terima invite',
                  onPressed: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AcceptInviteScreen()));
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
                    await prefs.remove(prefKeySelectedGroup);
                    
                    final list = await DBService.instance.getMessagesForGroup(null);
                    messagesState.value = list.reversed.toList();
                    
                    await subscribeRealtime(null);
                  },
                ),
                const SizedBox(width: 8),
                ...groupsState.value.map((g) => Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: GestureDetector(
                        onLongPress: () async {
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

                          if (!context.mounted) return;

                          if (choice == 'edit') {
                            final editNameCtrl = TextEditingController(text: g.name);
                            await showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Ubah Nama Grup'),
                                content: TextField(controller: editNameCtrl, decoration: const InputDecoration(labelText: 'Nama baru')),
                                actions: [
                                  TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Batal')),
                                  ElevatedButton(
                                    onPressed: () async {
                                      final newName = editNameCtrl.text.trim();
                                      if (newName.isNotEmpty) {
                                        final updated = Group(
                                          id: g.id,
                                          name: newName,
                                          description: g.description,
                                          icon: g.icon,
                                          createdAt: g.createdAt,
                                          createdBy: g.createdBy,
                                        );
                                        await DBService.instance.updateGroup(updated);
                                        final gs2 = await DBService.instance.getGroups();
                                        groupsState.value = gs2;
                                      }
                                      if (ctx.mounted) Navigator.of(ctx).pop();
                                    },
                                    child: const Text('Simpan'),
                                  ),
                                ],
                              ),
                            );
                          } else if (choice == 'settings') {
                            final deleted = await Navigator.of(context).push<bool>(
                              MaterialPageRoute(
                                builder: (_) => GroupSettingsScreen(
                                  groupId: g.id,
                                  currentUserId: AuthService.instance.userId,
                                ),
                              ),
                            );
                            if (deleted == true) {
                              final gs2 = await DBService.instance.getGroups();
                              groupsState.value = gs2;
                              if (selectedGroupId.value == g.id) {
                                selectedGroupId.value = null;
                                final prefs = await SharedPreferences.getInstance();
                                await prefs.remove(prefKeySelectedGroup);
                                final list = await DBService.instance.getMessagesForGroup(null);
                                messagesState.value = list.reversed.toList();
                                await subscribeRealtime(null);
                              }
                            }
                          } else if (choice == 'delete') {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Hapus Grup'),
                                content: const Text('Yakin ingin menghapus grup ini?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Batal')),
                                  ElevatedButton(
                                    onPressed: () => Navigator.of(ctx).pop(true),
                                    child: const Text('Hapus'),
                                  ),
                                ],
                              ),
                            );
                            
                            if (confirm == true) {
                              await DBService.instance.deleteGroup(g.id);
                              final gs2 = await DBService.instance.getGroups();
                              groupsState.value = gs2;
                              
                              if (selectedGroupId.value == g.id) {
                                selectedGroupId.value = null;
                                final prefs = await SharedPreferences.getInstance();
                                await prefs.remove(prefKeySelectedGroup);
                                final list = await DBService.instance.getMessagesForGroup(null);
                                messagesState.value = list.reversed.toList();
                                await subscribeRealtime(null);
                              }
                            }
                          }
                        },
                        child: ChoiceChip(
                          label: Text(g.name),
                          selected: selectedGroupId.value == g.id,
                          onSelected: (_) async {
                            selectedGroupId.value = g.id;
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString(prefKeySelectedGroup, g.id);
                            
                            final list = await DBService.instance.getMessagesForGroup(g.id);
                            messagesState.value = list.reversed.toList();
                            
                            await subscribeRealtime(g.id);
                          },
                        ),
                      ),
                    )),
                const SizedBox(width: 12),
              ],
            ),
          ),
          
          // Messages list
          Expanded(
            child: messagesState.value.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text(
                          'Belum ada pesan',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Mulai chat dengan mengirim pesan!',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  )
                : AnimatedList(
                    key: listKey.value,
                    controller: scrollController,
                    reverse: true,
                    initialItemCount: messagesState.value.length,
                    itemBuilder: (context, index, animation) {
                      final msg = messagesState.value[index];
                      final isMe = !msg.isSystem;
                      final showDate = index == messagesState.value.length - 1 ||
                          (index < messagesState.value.length - 1 &&
                              !_isSameDay(msg.createdAt, messagesState.value[index + 1].createdAt));
                      
                      return SizeTransition(
                        sizeFactor: animation,
                        child: Column(
                          children: [
                            // Date separator
                            if (showDate)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    _formatDateSeparator(msg.createdAt),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            
                            // Message bubble
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                              child: Row(
                                mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  // Avatar for system/group messages
                                  if (!isMe && selectedGroupId.value != null) ...[
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade100,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Icon(
                                          Icons.smart_toy,
                                          size: 18,
                                          color: Colors.blue.shade700,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  
                                  // Message content
                                  Flexible(
                                    child: GestureDetector(
                                      onLongPress: () async {
                                        final choice = await showModalBottomSheet<String?>(
                                          context: context,
                                          builder: (ctx) => SafeArea(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                ListTile(
                                                  leading: const Icon(Icons.delete, color: Colors.red),
                                                  title: const Text('Hapus Pesan'),
                                                  onTap: () => Navigator.of(ctx).pop('delete'),
                                                ),
                                                ListTile(
                                                  leading: const Icon(Icons.close),
                                                  title: const Text('Batal'),
                                                  onTap: () => Navigator.of(ctx).pop(null),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                        
                                        if (choice == 'delete' && context.mounted) {
                                          final confirm = await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text('Hapus Pesan'),
                                              content: const Text('Yakin ingin menghapus pesan ini dan transaksi terkait?'),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.of(ctx).pop(false),
                                                  child: const Text('Batal'),
                                                ),
                                                ElevatedButton(
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: Colors.red,
                                                    foregroundColor: Colors.white,
                                                  ),
                                                  onPressed: () => Navigator.of(ctx).pop(true),
                                                  child: const Text('Hapus'),
                                                ),
                                              ],
                                            ),
                                          );
                                          
                                          if (confirm == true && context.mounted) {
                                            await DBService.instance.deleteMessage(msg.id);
                                            final idx = messagesState.value.indexWhere((m) => m.id == msg.id);
                                            if (idx != -1) {
                                              messagesState.value = messagesState.value.where((m) => m.id != msg.id).toList();
                                              listKey.value.currentState?.removeItem(
                                                idx,
                                                (context, animation) => const SizedBox.shrink(),
                                                duration: const Duration(milliseconds: 300),
                                              );
                                            }
                                            
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Pesan berhasil dihapus')),
                                              );
                                            }
                                          }
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: isMe 
                                              ? const Color(0xFF128C7E) // WhatsApp green
                                              : Colors.white,
                                          borderRadius: BorderRadius.only(
                                            topLeft: const Radius.circular(16),
                                            topRight: const Radius.circular(16),
                                            bottomLeft: Radius.circular(isMe ? 16 : 4),
                                            bottomRight: Radius.circular(isMe ? 4 : 16),
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: 0.08),
                                              blurRadius: 3,
                                              offset: const Offset(0, 1),
                                            ),
                                          ],
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // Group sender name (if in group and not from me)
                                            if (!isMe && selectedGroupId.value != null) ...[
                                              Text(
                                                'Sistem',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.blue.shade700,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                            ],
                                            
                                            // Message text
                                            Text(
                                              msg.text,
                                              style: TextStyle(
                                                fontSize: 15,
                                                color: isMe ? Colors.white : Colors.black87,
                                                height: 1.4,
                                              ),
                                            ),
                                            
                                            const SizedBox(height: 4),
                                            
                                            // Timestamp and status
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  DateFormat('HH:mm').format(msg.createdAt),
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: isMe 
                                                        ? Colors.white.withValues(alpha: 0.7)
                                                        : Colors.grey.shade600,
                                                  ),
                                                ),
                                                if (isMe) ...[
                                                  const SizedBox(width: 4),
                                                  Icon(
                                                    Icons.done_all,
                                                    size: 14,
                                                    color: selectedGroupId.value != null
                                                        ? Colors.blue.shade200
                                                        : Colors.white.withValues(alpha: 0.7),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  
                                  // Spacer for alignment
                                  if (!isMe && selectedGroupId.value == null)
                                    const SizedBox(width: 40),
                                  if (isMe)
                                    const SizedBox(width: 40),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          
          // Input bar
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Voice button
                IconButton(
                  icon: Icon(isListening.value ? Icons.mic : Icons.mic_none),
                  color: isListening.value ? Colors.red : null,
                  onPressed: () async {
                    if (isListening.value) {
                      isListening.value = false;
                      try {
                        await VoiceService.instance.stopListening();
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error voice: $e')));
                        }
                      }
                    } else {
                      isListening.value = true;
                      try {
                        await VoiceService.instance.startListening(
                          onResult: (result) async {
                            if (result.isNotEmpty && context.mounted) {
                              final parsed = await ParserService.instance.parseText(result);
                              if (parsed != null) {
                                await promptConfirm(parsed, source: 'voice', autoSave: true);
                              } else {
                                await sendSystemReply('Maaf, saya tidak dapat memahami input voice tersebut.', groupId: selectedGroupId.value);
                              }
                            }
                          },
                        );
                      } catch (e) {
                        isListening.value = false;
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error memulai voice: $e')));
                        }
                      }
                    }
                  },
                ),
                
                // OCR button
                IconButton(
                  icon: const Icon(Icons.camera_alt),
                  onPressed: () async {
                    final choice = await showModalBottomSheet<String>(
                      context: context,
                      builder: (ctx) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.camera_alt),
                              title: const Text('Scan dari Kamera'),
                              onTap: () => Navigator.pop(ctx, 'camera'),
                            ),
                            ListTile(
                              leading: const Icon(Icons.photo_library),
                              title: const Text('Ambil dari Galeri'),
                              onTap: () => Navigator.pop(ctx, 'gallery'),
                            ),
                          ],
                        ),
                      ),
                    );
                    
                    if (choice == null || !context.mounted) return;
                    
                    try {
                      final receipt = choice == 'camera'
                          ? await OCRService.instance.scanFromCamera()
                          : await OCRService.instance.scanFromGallery();
                      
                      if (receipt == null || !context.mounted) return;
                      
                      double totalAmount = receipt.totalAmount;
                      if (receipt.items.isNotEmpty) {
                        final itemsTotal = receipt.items.fold<double>(0, (sum, item) => sum + item.price);
                        final selection = await showDialog<String>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Preview Struk'),
                            content: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('Toko: ${receipt.merchantName}'),
                                  const SizedBox(height: 8),
                                  Text('Total Struk: Rp ${nf.format(receipt.totalAmount)}'),
                                  Text('Total Item: Rp ${nf.format(itemsTotal)}'),
                                  const SizedBox(height: 12),
                                  const Text('Item (ringkas):'),
                                  const SizedBox(height: 6),
                                  SizedBox(
                                    height: 200,
                                    child: ListView.builder(
                                      shrinkWrap: true,
                                      itemCount: receipt.items.length > 10 ? 10 : receipt.items.length,
                                      itemBuilder: (c, i) {
                                        final it = receipt.items[i];
                                        return Text('- ${it.name} (Rp ${nf.format(it.price)})');
                                      },
                                    ),
                                  ),
                                  if (receipt.items.length > 10)
                                    const Padding(
                                      padding: EdgeInsets.only(top: 6),
                                      child: Text('...dan item lainnya', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                    ),
                                ],
                              ),
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Batal')),
                              TextButton(onPressed: () => Navigator.pop(ctx, 'items'), child: const Text('Pakai Total Item')),
                              ElevatedButton(onPressed: () => Navigator.pop(ctx, 'receipt'), child: const Text('Pakai Total Struk')),
                            ],
                          ),
                        );
                        
                        if (selection == 'cancel' || selection == null) return;
                        if (selection == 'items') {
                          totalAmount = itemsTotal;
                        }
                      }

                      if (!context.mounted) return;
                      
                      final total = totalAmount.toStringAsFixed(0);
                      final dateText = receipt.date != null ? ' pada ${receipt.date}' : '';
                      final ocrText = 'Belanja ${receipt.merchantName} Rp $total$dateText';
                      final parsed = await ParserService.instance.parseText(ocrText);
                      
                      ParsedTransaction ocrParsed;
                      if (parsed != null) {
                        ocrParsed = parsed;
                      } else {
                        ocrParsed = ParsedTransaction(
                          amount: totalAmount,
                          currency: 'IDR',
                          category: 'Belanja',
                          description: ocrText,
                          isIncome: false,
                          type: 'expense',
                        );
                      }

                      await promptConfirm(ocrParsed, source: 'ocr', autoSave: true);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal membaca struk: $e')));
                      }
                    }
                  },
                ),
                
                // Text input
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: TextField(
                      controller: controller,
                      scrollController: inputScrollController,
                      decoration: const InputDecoration(
                        hintText: 'Ketik pesan...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (text) async {
                        final trimmed = text.trim();
                        controller.clear();
                        await sendMessage(trimmed);
                      },
                    ),
                  ),
                ),
                
                // Send button
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF128C7E),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send),
                    color: Colors.white,
                    iconSize: 20,
                    onPressed: () async {
                      final text = controller.text.trim();
                      if (text.isEmpty) return;
                      controller.clear();
                      await sendMessage(text);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
