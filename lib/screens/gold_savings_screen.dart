import 'package:flutter/material.dart';
import 'package:catatan_keuangan_pintar/services/db_service.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GoldSavingsScreen extends HookWidget {
  const GoldSavingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final nf = NumberFormat('#,##0', 'id');
    final uuid = const Uuid();
    final types = useState<List<GoldType>>([]);
    final holdings = useState<List<GoldHolding>>([]);
    final transactions = useState<List<GoldTransaction>>([]);
    final groups = useState<List<Group>>([]);
    final selectedGroupId = useState<String?>(null);
    final isLoading = useState(true);
    final selectedTab = useState(0); // 0 = Holdings, 1 = Transactions

    Future<void> loadData() async {
      isLoading.value = true;
      types.value = await DBService.instance.getGoldTypes();
      holdings.value = await DBService.instance.getGoldHoldings(groupId: selectedGroupId.value);
      transactions.value = await DBService.instance.getGoldTransactions(groupId: selectedGroupId.value);
      isLoading.value = false;
    }

    useEffect(() {
      Future<void>(() async {
        final gs = await DBService.instance.getGroups();
        groups.value = gs;
        final prefs = await SharedPreferences.getInstance();
        final savedGroupId = prefs.getString('selectedGroupId');
        if (savedGroupId != null && gs.any((g) => g.id == savedGroupId)) {
          selectedGroupId.value = savedGroupId;
        } else {
          selectedGroupId.value = null;
        }
        await loadData();
      });
      return null;
    }, const []);

    useEffect(() {
      loadData();
      return null;
    }, [selectedGroupId.value]);

    // --- Type Editor ---
    Future<void> _showTypeEditor({GoldType? type}) async {
      final nameCtrl = TextEditingController(text: type?.name ?? '');
      final priceCtrl = TextEditingController(
        text: type?.pricePerGram.toStringAsFixed(0) ?? '',
      );
      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(type == null ? 'Tambah Tipe Emas' : 'Edit Tipe Emas'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Nama (contoh: Antam, UBS)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.label_outline),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Harga jual per gram (Rp)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.monetization_on_outlined),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Simpan'),
            ),
          ],
        ),
      );
      if (result == true) {
        final name = nameCtrl.text.trim();
        final price = double.tryParse(
                priceCtrl.text.replaceAll('.', '').replaceAll(',', '')) ??
            0;
        if (name.isEmpty || price <= 0) return;
        if (type == null) {
          await DBService.instance.insertGoldType(
            GoldType(
              id: uuid.v4(),
              name: name,
              pricePerGram: price,
              createdAt: DateTime.now(),
            ),
          );
        } else {
          await DBService.instance.updateGoldType(
            GoldType(
              id: type.id,
              name: name,
              pricePerGram: price,
              createdAt: type.createdAt,
              updatedAt: DateTime.now(),
            ),
          );
        }
        await loadData();
      }
    }

    // --- Holdings Editor with Purchase Price ---
    Future<void> _showHoldingsEditor({GoldHolding? holding}) async {
      if (types.value.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tambahkan tipe emas terlebih dahulu')),
        );
        return;
      }
      final activeGroupId = holding?.groupId ?? selectedGroupId.value;
      final activeScope = activeGroupId == null ? 'personal' : 'group';
      String selectedTypeId = holding?.typeId ?? types.value.first.id;
      final gramsCtrl = TextEditingController(
        text: holding != null ? holding.grams.toStringAsFixed(2) : '',
      );
      final purchasePriceCtrl = TextEditingController(
        text: holding?.purchasePrice?.toStringAsFixed(0) ?? '',
      );

      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setState) {
            final type = types.value.firstWhere(
              (t) => t.id == selectedTypeId,
              orElse: () =>
                  GoldType(id: '', name: '', pricePerGram: 0, createdAt: DateTime.now()),
            );
            final grams =
                double.tryParse(gramsCtrl.text.replaceAll(',', '.')) ?? 0;
            final buyPrice = double.tryParse(
                    purchasePriceCtrl.text.replaceAll('.', '').replaceAll(',', '')) ??
                0;
            final currentValue = grams * type.pricePerGram;
            final costBasis = grams * buyPrice;
            final gainLoss = buyPrice > 0 ? currentValue - costBasis : 0.0;
            final gainLossPct =
                costBasis > 0 ? (gainLoss / costBasis * 100) : 0.0;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(holding == null ? 'Tambah Holdings' : 'Edit Holdings'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedTypeId,
                      items: types.value
                          .map((t) =>
                              DropdownMenuItem(value: t.id, child: Text(t.name)))
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => selectedTypeId = v);
                      },
                      decoration: InputDecoration(
                        labelText: 'Tipe Emas',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        prefixIcon: const Icon(Icons.stars),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: gramsCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Jumlah (gram)',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        prefixIcon: const Icon(Icons.scale),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: purchasePriceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Harga beli per gram (Rp)',
                        helperText: 'Harga jual saat ini: Rp ${nf.format(type.pricePerGram)}/g',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        prefixIcon: const Icon(Icons.shopping_cart_outlined),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    if (buyPrice > 0 && grams > 0) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: gainLoss >= 0
                              ? Colors.green.shade50
                              : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: gainLoss >= 0
                                ? Colors.green.shade300
                                : Colors.red.shade300,
                          ),
                        ),
                        child: Column(
                          children: [
                            _SummaryRow('Nilai Beli', 'Rp ${nf.format(costBasis)}'),
                            const SizedBox(height: 4),
                            _SummaryRow('Nilai Jual Saat Ini', 'Rp ${nf.format(currentValue)}'),
                            const Divider(height: 12),
                            _SummaryRow(
                              gainLoss >= 0 ? 'Keuntungan' : 'Kerugian',
                              '${gainLoss >= 0 ? '+' : ''}Rp ${nf.format(gainLoss.abs())} (${gainLossPct >= 0 ? '+' : ''}${gainLossPct.toStringAsFixed(1)}%)',
                              valueColor: gainLoss >= 0 ? Colors.green : Colors.red,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Batal'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Simpan'),
                ),
              ],
            );
          },
        ),
      );

      if (result == true) {
        final grams =
            double.tryParse(gramsCtrl.text.replaceAll(',', '.')) ?? 0;
        final purchasePrice = double.tryParse(
                purchasePriceCtrl.text.replaceAll('.', '').replaceAll(',', '')) ??
            0;
        if (grams <= 0) return;

        final db = await DBService.instance.database;
        if (holding == null) {
          final newHolding = GoldHolding(
            id: uuid.v4(),
            typeId: selectedTypeId,
            grams: grams,
            purchasePrice: purchasePrice > 0 ? purchasePrice : null,
            createdAt: DateTime.now(),
            scope: activeScope,
            groupId: activeGroupId,
          );
          await db.insert('gold_holdings', newHolding.toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace);
        } else {
          await db.update(
            'gold_holdings',
            {
              'typeId': selectedTypeId,
              'grams': grams,
              'purchasePrice': purchasePrice > 0 ? purchasePrice : null,
              'updatedAt': DateTime.now().millisecondsSinceEpoch,
              'scope': activeScope,
              'groupId': activeGroupId,
            },
            where: 'id = ?',
            whereArgs: [holding.id],
          );
        }
        await loadData();
      }
    }

    // --- Transaction Editor ---
    Future<void> _showTransactionEditor() async {
      if (types.value.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tambahkan tipe emas dulu')),
        );
        return;
      }
      final activeGroupId = selectedGroupId.value;
      final activeScope = activeGroupId == null ? 'personal' : 'group';
      String selectedTypeId = types.value.first.id;
      String txType = 'buy';
      String mode = 'physical';
      DateTime txDate = DateTime.now();
      final gramsCtrl = TextEditingController();
      final priceCtrl = TextEditingController(
          text: types.value.first.pricePerGram.toStringAsFixed(0));
      final noteCtrl = TextEditingController();

      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Transaksi Emas'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedTypeId,
                    items: types.value
                        .map((t) => DropdownMenuItem(
                            value: t.id, child: Text(t.name)))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        selectedTypeId = v;
                        final t = types.value.firstWhere((e) => e.id == v);
                        priceCtrl.text = t.pricePerGram.toStringAsFixed(0);
                      });
                    },
                    decoration: InputDecoration(
                      labelText: 'Tipe Emas',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: txType,
                    items: const [
                      DropdownMenuItem(value: 'buy', child: Text('Beli')),
                      DropdownMenuItem(value: 'sell', child: Text('Jual')),
                      DropdownMenuItem(value: 'installment', child: Text('Cicilan')),
                    ],
                    onChanged: (v) => setState(() => txType = v ?? txType),
                    decoration: InputDecoration(
                      labelText: 'Jenis Transaksi',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: mode,
                    items: const [
                      DropdownMenuItem(value: 'physical', child: Text('Fisik')),
                      DropdownMenuItem(value: 'digital', child: Text('Digital')),
                      DropdownMenuItem(value: 'installment', child: Text('Cicilan')),
                    ],
                    onChanged: (v) => setState(() => mode = v ?? mode),
                    decoration: InputDecoration(
                      labelText: 'Tipe Pembelian',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: gramsCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Jumlah (gram)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Harga per gram (Rp)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteCtrl,
                    decoration: InputDecoration(
                      labelText: 'Catatan (opsional)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Tanggal'),
                    subtitle: Text(DateFormat('dd MMM yyyy', 'id').format(txDate)),
                    trailing: IconButton(
                      icon: const Icon(Icons.calendar_today),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: txDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(const Duration(days: 3650)),
                          locale: const Locale('id'),
                        );
                        if (picked != null) setState(() => txDate = picked);
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Simpan'),
              ),
            ],
          ),
        ),
      );

      if (result == true) {
        final grams = double.tryParse(gramsCtrl.text.replaceAll(',', '.')) ?? 0;
        final price = double.tryParse(
                priceCtrl.text.replaceAll('.', '').replaceAll(',', '')) ?? 0;
        if (grams <= 0 || price <= 0) return;
        final total = grams * price;
        await DBService.instance.insertGoldTransaction(
          GoldTransaction(
            id: uuid.v4(),
            typeId: selectedTypeId,
            txType: txType,
            mode: mode,
            grams: grams,
            pricePerGram: price,
            totalValue: total,
            date: txDate,
            note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
            createdAt: DateTime.now(),
            scope: activeScope,
            groupId: activeGroupId,
          ),
        );
        await loadData();
      }
    }

    // --- Delete Holdings ---
    Future<void> _deleteHolding(GoldHolding holding) async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Hapus Emas?'),
          content: const Text('Apakah Anda yakin ingin menghapus data emas ini?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Hapus'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        final db = await DBService.instance.database;
        await db.update(
          'gold_holdings',
          {'deletedAt': DateTime.now().millisecondsSinceEpoch},
          where: 'id = ?',
          whereArgs: [holding.id],
        );
        await loadData();
      }
    }

    if (isLoading.value) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // --- Calculate Portfolio Summary ---
    double totalGrams = 0;
    double totalCurrentValue = 0;
    double totalCostBasis = 0;
    for (final h in holdings.value) {
      final t = types.value.firstWhere(
        (e) => e.id == h.typeId,
        orElse: () => GoldType(id: '', name: '', pricePerGram: 0, createdAt: DateTime.now()),
      );
      totalGrams += h.grams;
      totalCurrentValue += h.grams * t.pricePerGram;
      if (h.purchasePrice != null) {
        totalCostBasis += h.grams * h.purchasePrice!;
      }
    }
    final totalGainLoss = totalCostBasis > 0 ? totalCurrentValue - totalCostBasis : 0.0;
    final totalGainLossPct =
        totalCostBasis > 0 ? (totalGainLoss / totalCostBasis * 100) : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tabungan Emas'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // --- Portfolio Summary Card ---
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.amber.shade700, Colors.amber.shade500],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.amber.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.stars, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Portfolio Emas',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (totalCostBasis > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: totalGainLoss >= 0
                              ? Colors.green.shade600
                              : Colors.red.shade600,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${totalGainLoss >= 0 ? '+' : ''}${totalGainLossPct.toStringAsFixed(1)}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _InfoColumn('Total Gram', '${totalGrams.toStringAsFixed(2)} g'),
                    const SizedBox(width: 24),
                    _InfoColumn('Nilai Saat Ini', 'Rp ${nf.format(totalCurrentValue)}'),
                  ],
                ),
                if (totalCostBasis > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          totalGainLoss >= 0 ? Icons.trending_up : Icons.trending_down,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            totalGainLoss >= 0
                                ? 'Untung Rp ${nf.format(totalGainLoss.abs())}'
                                : 'Rugi Rp ${nf.format(totalGainLoss.abs())}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Wallet Selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: selectedGroupId.value,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Row(
                        children: [
                          Icon(Icons.person, size: 20),
                          SizedBox(width: 8),
                          Text('Personal'),
                        ],
                      ),
                    ),
                    ...groups.value.map((g) => DropdownMenuItem(
                      value: g.id,
                      child: Row(
                        children: [
                          const Icon(Icons.group, size: 20),
                          const SizedBox(width: 8),
                          Text(g.name),
                        ],
                      ),
                    )),
                  ],
                  onChanged: (v) async {
                    selectedGroupId.value = v;
                    final prefs = await SharedPreferences.getInstance();
                    if (v == null) {
                      await prefs.remove('selectedGroupId');
                    } else {
                      await prefs.setString('selectedGroupId', v);
                    }
                  },
                ),
              ),
            ),
          ),

          // --- Tab Selector ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Emas Saya'), icon: Icon(Icons.account_balance_wallet)),
                ButtonSegment(value: 1, label: Text('Transaksi'), icon: Icon(Icons.receipt_long)),
              ],
              selected: {selectedTab.value},
              onSelectionChanged: (s) => selectedTab.value = s.first,
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: Colors.amber.shade100,
              ),
            ),
          ),

          const SizedBox(height: 12),

          // --- Tab Content ---
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: selectedTab.value == 0
                  ? _buildHoldingsTab(
                      context, holdings.value, types.value, nf,
                      _showHoldingsEditor, _deleteHolding, _showTypeEditor)
                  : _buildTransactionsTab(
                      context, transactions.value, types.value, nf),
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'gold_holding',
            onPressed: () => _showHoldingsEditor(),
            icon: const Icon(Icons.add),
            label: const Text('Tambah Emas'),
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'gold_tx',
            onPressed: _showTransactionEditor,
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Transaksi'),
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'gold_type',
            onPressed: () => _showTypeEditor(),
            icon: const Icon(Icons.category),
            label: const Text('Tipe Emas'),
            backgroundColor: Colors.amber.shade700,
            foregroundColor: Colors.white,
          ),
        ],
      ),
    );
  }

  // --- Holdings Tab ---
  Widget _buildHoldingsTab(
    BuildContext context,
    List<GoldHolding> holdings,
    List<GoldType> types,
    NumberFormat nf,
    Future<void> Function({GoldHolding? holding}) onEdit,
    Future<void> Function(GoldHolding) onDelete,
    Future<void> Function({GoldType? type}) onTypeEdit,
  ) {
    final typeSection = Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tipe Emas',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (types.isEmpty)
            Text('Belum ada tipe emas', style: TextStyle(color: Colors.grey.shade600)),
          ...types.map((t) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t.name),
                subtitle: Text('Rp ${nf.format(t.pricePerGram)}/g'),
                trailing: IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => onTypeEdit(type: t),
                ),
              )),
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        typeSection,
        if (holdings.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.stars, size: 60, color: Colors.amber.shade300),
                const SizedBox(height: 16),
                Text('Belum ada kepemilikan emas',
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
                const SizedBox(height: 8),
                Text('Tambahkan tipe emas lalu catat emas yang kamu pegang',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
              ],
            ),
          ),
        ...holdings.map((holding) {
          final type = types.firstWhere(
            (t) => t.id == holding.typeId,
            orElse: () => GoldType(id: '', name: 'Unknown', pricePerGram: 0, createdAt: DateTime.now()),
          );
          final currentValue = holding.grams * type.pricePerGram;
          final hasPurchasePrice = holding.purchasePrice != null && holding.purchasePrice! > 0;
          final costBasis = hasPurchasePrice ? holding.grams * holding.purchasePrice! : 0.0;
          final gainLoss = hasPurchasePrice ? currentValue - costBasis : 0.0;
          final gainLossPct = costBasis > 0 ? (gainLoss / costBasis * 100) : 0.0;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onEdit(holding: holding),
              onLongPress: () => onDelete(holding),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.stars, color: Colors.amber.shade700, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(type.name,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              Text('${holding.grams.toStringAsFixed(2)} gram',
                                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('Rp ${nf.format(currentValue)}',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            if (hasPurchasePrice)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: gainLoss >= 0 ? Colors.green.shade50 : Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${gainLoss >= 0 ? '+' : ''}${gainLossPct.toStringAsFixed(1)}%',
                                  style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.bold,
                                    color: gainLoss >= 0 ? Colors.green : Colors.red,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    if (hasPurchasePrice) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Harga Beli',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                  Text('Rp ${nf.format(holding.purchasePrice!)}/g',
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                            Icon(Icons.arrow_forward, size: 16, color: Colors.grey.shade400),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('Harga Jual',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                  Text('Rp ${nf.format(type.pricePerGram)}/g',
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            gainLoss >= 0
                                ? 'Keuntungan: +Rp ${nf.format(gainLoss.abs())}'
                                : 'Kerugian: -Rp ${nf.format(gainLoss.abs())}',
                            style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold,
                              color: gainLoss >= 0 ? Colors.green : Colors.red,
                            ),
                          ),
                          Text('long-press untuk hapus',
                              style: TextStyle(fontSize: 10, color: Colors.grey.shade400,
                                  fontStyle: FontStyle.italic)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  // --- Transactions Tab ---
  Widget _buildTransactionsTab(
    BuildContext context,
    List<GoldTransaction> transactions,
    List<GoldType> types,
    NumberFormat nf,
  ) {
    if (transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 60, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('Belum ada transaksi emas',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: transactions.length,
      itemBuilder: (context, index) {
        final tx = transactions[index];
        final type = types.firstWhere(
          (t) => t.id == tx.typeId,
          orElse: () => GoldType(id: '', name: '-', pricePerGram: 0, createdAt: DateTime.now()),
        );
        final isSell = tx.txType == 'sell';
        final label = isSell ? 'Jual' : tx.txType == 'installment' ? 'Cicilan' : 'Beli';
        final modeLabel = tx.mode == 'digital' ? 'Digital' : tx.mode == 'installment' ? 'Cicilan' : 'Fisik';

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSell ? Colors.red.shade50 : Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isSell ? Icons.sell : Icons.shopping_cart,
                color: isSell ? Colors.red : Colors.green,
                size: 22,
              ),
            ),
            title: Text('${type.name} - $label',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              '${tx.grams.toStringAsFixed(2)}g x Rp ${nf.format(tx.pricePerGram)}/g - $modeLabel'
              '${tx.note != null ? '\n${tx.note}' : ''}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Rp ${nf.format(tx.totalValue)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isSell ? Colors.red : Colors.green,
                      fontSize: 14,
                    )),
                Text(DateFormat('dd MMM yy', 'id').format(tx.date),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ],
            ),
          ),
        );
      },
    );
  }
}

// --- Helper Widgets ---

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _SummaryRow(this.label, this.value, {this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
        Text(value,
            style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.bold,
              color: valueColor ?? Colors.grey.shade900,
            )),
      ],
    );
  }
}

class _InfoColumn extends StatelessWidget {
  final String label;
  final String value;
  const _InfoColumn(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
