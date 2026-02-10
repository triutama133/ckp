import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:catatan_keuangan_pintar/services/db_service.dart';
import 'package:intl/intl.dart';

class TransactionHistoryScreen extends HookWidget {
  const TransactionHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final nf = NumberFormat('#,##0', 'id');
    final df = DateFormat('dd MMM yyyy', 'id');
    
    // State
    final startDate = useState<DateTime?>(null);
    final endDate = useState<DateTime?>(null);
    final selectedFilter = useState<String>('all'); // all, income, expense, saving, investment
    final selectedGroupId = useState<String?>('personal'); // personal, all, or group ID
    final groups = useState<List<Group>>([]);
    final categories = useState<List<Category>>([]);
    final transactions = useState<List<TransactionModel>>([]);
    final isLoading = useState(false);
    
    // Load groups
    Future<void> loadGroups() async {
      try {
        final gs = await DBService.instance.getGroups();
        groups.value = gs;
      } catch (e) {
        // Silent fail
      }
    }

    // Load categories
    Future<void> loadCategories() async {
      try {
        final cats = await DBService.instance.getCategories();
        categories.value = cats;
      } catch (e) {
        // Silent fail
      }
    }
    
    // Load transactions
    Future<void> loadTransactions() async {
      isLoading.value = true;
      try {
        final now = DateTime.now();
        final start = startDate.value ?? DateTime(now.year, now.month, 1);
        final end = endDate.value ?? DateTime(now.year, now.month + 1, 1).subtract(const Duration(milliseconds: 1));
        
        // Group filter
        String? groupFilter;
        if (selectedGroupId.value == 'personal') {
          groupFilter = null; // null means personal
        } else if (selectedGroupId.value != 'all') {
          groupFilter = selectedGroupId.value;
        }
        
        final allTx = await DBService.instance.getTransactionsBetween(start, end);
        final scopedTx = selectedGroupId.value == 'all'
            ? allTx
            : (groupFilter == null
                ? allTx.where((t) => t.groupId == null).toList()
                : allTx.where((t) => t.groupId == groupFilter).toList());
        
        // Apply filter
        List<TransactionModel> filtered;
        switch (selectedFilter.value) {
          case 'income':
            filtered = scopedTx.where((tx) => tx.isIncome).toList();
            break;
          case 'expense':
            filtered = scopedTx.where((tx) => !tx.isIncome && tx.type != 'saving' && tx.type != 'investment').toList();
            break;
          case 'saving':
            filtered = scopedTx.where((tx) => tx.type == 'saving' || tx.type == 'saving_out').toList();
            break;
          case 'investment':
            filtered = scopedTx.where((tx) => tx.type == 'investment' || tx.type == 'investment_out').toList();
            break;
          default:
            filtered = scopedTx;
        }
        
        transactions.value = filtered;
      } catch (e) {
        // Handle error
      } finally {
        isLoading.value = false;
      }
    }
    
    // Calculate totals
    double getTotalIncome() {
      return transactions.value.where((tx) => tx.isIncome).fold(0.0, (sum, tx) => sum + tx.amount);
    }
    
    double getTotalExpense() {
      return transactions.value.where((tx) => !tx.isIncome && tx.type != 'saving' && tx.type != 'investment').fold(0.0, (sum, tx) => sum + tx.amount);
    }
    
    double getTotalSaving() {
      final saved = transactions.value.where((tx) => tx.type == 'saving').fold(0.0, (sum, tx) => sum + tx.amount);
      final withdrawn = transactions.value.where((tx) => tx.type == 'saving_out').fold(0.0, (sum, tx) => sum + tx.amount);
      return saved - withdrawn;
    }
    
    double getTotalInvestment() {
      final invested = transactions.value.where((tx) => tx.type == 'investment').fold(0.0, (sum, tx) => sum + tx.amount);
      final withdrawn = transactions.value.where((tx) => tx.type == 'investment_out').fold(0.0, (sum, tx) => sum + tx.amount);
      return invested - withdrawn;
    }
    
    String getCategoryName(String? categoryId) {
      if (categoryId == null) return '-';
      final cat = categories.value.firstWhere(
        (c) => c.id == categoryId,
        orElse: () => Category(
          id: '',
          name: categoryId,
          type: '',
          createdAt: DateTime.now(),
        ),
      );
      return cat.name;
    }

    // Edit transaction
    Future<void> editTransaction(TransactionModel tx) async {
      final amountCtrl = TextEditingController(text: tx.amount.toStringAsFixed(0));
      final categoryCtrl = TextEditingController(text: getCategoryName(tx.category));
      final descCtrl = TextEditingController(text: tx.description ?? '');
      final dateCtrl = TextEditingController(text: DateFormat('dd/MM/yyyy').format(tx.date));
      
      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Edit Transaksi'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amountCtrl,
                  decoration: const InputDecoration(labelText: 'Jumlah'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: categoryCtrl,
                  decoration: const InputDecoration(labelText: 'Kategori'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Deskripsi'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dateCtrl,
                  decoration: const InputDecoration(labelText: 'Tanggal (dd/MM/yyyy)'),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: tx.date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      dateCtrl.text = DateFormat('dd/MM/yyyy').format(picked);
                    }
                  },
                  readOnly: true,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () async {
                final newAmount = double.tryParse(amountCtrl.text.replaceAll('.', '').replaceAll(',', '')) ?? tx.amount;
                DateTime? newDate;
                try {
                  final parts = dateCtrl.text.split('/');
                  if (parts.length == 3) {
                    newDate = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
                  }
                } catch (_) {}
                
                final updated = TransactionModel(
                  id: tx.id,
                  messageId: tx.messageId,
                  amount: newAmount,
                  currency: tx.currency,
                  category: tx.category, // Keep original category for now
                  description: descCtrl.text.trim().isEmpty ? tx.description : descCtrl.text.trim(),
                  date: newDate ?? tx.date,
                  createdAt: tx.createdAt,
                  isIncome: tx.isIncome,
                  type: tx.type,
                  scope: tx.scope,
                  groupId: tx.groupId,
                );
                
                await DBService.instance.insertTransaction(updated);
                Navigator.of(ctx).pop(true);
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      );
      
      if (result == true) {
        await loadTransactions();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Transaksi berhasil diupdate')),
          );
        }
      }
    }
    
    // Delete transaction
    Future<void> deleteTransaction(TransactionModel tx) async {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Hapus Transaksi'),
          content: Text('Yakin ingin menghapus transaksi "${tx.description ?? tx.category ?? 'Tidak ada deskripsi'}"?'),
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
      
      if (confirm == true) {
        await DBService.instance.deleteTransaction(tx.id);
        await loadTransactions();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Transaksi berhasil dihapus')),
          );
        }
      }
    }
    
    // Pick month
    Future<void> pickDateRange() async {
      final now = DateTime.now();
      
      // Show template selection dialog
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Pilih Periode'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.today),
                title: const Text('Hari Ini'),
                onTap: () => Navigator.of(ctx).pop('today'),
              ),
              ListTile(
                leading: const Icon(Icons.view_week),
                title: const Text('Minggu Ini'),
                onTap: () => Navigator.of(ctx).pop('week'),
              ),
              ListTile(
                leading: const Icon(Icons.calendar_month),
                title: const Text('Bulan Ini'),
                onTap: () => Navigator.of(ctx).pop('month'),
              ),
              ListTile(
                leading: const Icon(Icons.calendar_today),
                title: const Text('Tahun Ini'),
                onTap: () => Navigator.of(ctx).pop('year'),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.date_range),
                title: const Text('Pilih Tanggal Custom'),
                onTap: () => Navigator.of(ctx).pop('custom'),
              ),
            ],
          ),
        ),
      );

      if (choice == null || !context.mounted) return;

      DateTime start, end;

      switch (choice) {
        case 'today':
          start = DateTime(now.year, now.month, now.day);
          end = DateTime(now.year, now.month, now.day, 23, 59, 59);
          break;
        case 'week':
          start = now.subtract(Duration(days: now.weekday - 1));
          end = start.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));
          break;
        case 'month':
          start = DateTime(now.year, now.month, 1);
          end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
          break;
        case 'year':
          start = DateTime(now.year, 1, 1);
          end = DateTime(now.year, 12, 31, 23, 59, 59);
          break;
        case 'custom':
          final initialStart = startDate.value ?? DateTime(now.year, now.month, now.day - 7);
          final initialEnd = endDate.value ?? now;
          final initialRange = DateTimeRange(start: initialStart, end: initialEnd);

          final picked = await showDateRangePicker(
            context: context,
            firstDate: DateTime(2000),
            lastDate: DateTime(now.year + 5),
            initialDateRange: initialRange,
          );

          if (picked == null) return;
          start = DateTime(picked.start.year, picked.start.month, picked.start.day);
          end = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
          break;
        default:
          return;
      }

      startDate.value = start;
      endDate.value = end;
      await loadTransactions();
    }
    
    // Initialize
    useEffect(() {
      loadGroups();
      loadCategories();
      loadTransactions();
      return null;
    }, [startDate.value, endDate.value, selectedFilter.value, selectedGroupId.value]);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Transaksi'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: loadTransactions,
          ),
        ],
      ),
      body: Column(
        children: [
          // Date Range Picker
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: InkWell(
              onTap: pickDateRange,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey.shade50,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.date_range, size: 22),
                    const SizedBox(width: 12),
                    Text(
                      startDate.value != null && endDate.value != null
                          ? '${df.format(startDate.value!)} - ${df.format(endDate.value!)}'
                          : 'Pilih Periode',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: startDate.value != null 
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.arrow_drop_down, color: Colors.grey.shade600),
                  ],
                ),
              ),
            ),
          ),
          
          // Group/Personal Filter
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.filter_alt, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Kantong:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: const Text('Personal'),
                          selected: selectedGroupId.value == 'personal',
                          onSelected: (_) {
                            selectedGroupId.value = 'personal';
                          },
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Semua'),
                          selected: selectedGroupId.value == 'all',
                          onSelected: (_) {
                            selectedGroupId.value = 'all';
                          },
                        ),
                        ...groups.value.map((g) => Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: ChoiceChip(
                            label: Text(g.name),
                            selected: selectedGroupId.value == g.id,
                            onSelected: (_) {
                              selectedGroupId.value = g.id;
                            },
                          ),
                        )),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Summary Cards
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade50,
            child: GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2,
              children: [
                _buildSummaryCard('Pemasukan', getTotalIncome(), Colors.green, nf),
                _buildSummaryCard('Pengeluaran', getTotalExpense(), Colors.red, nf),
                _buildSummaryCard('Tabungan', getTotalSaving(), Colors.blue, nf),
                _buildSummaryCard('Investasi', getTotalInvestment(), Colors.purple, nf),
              ],
            ),
          ),
          
          // Filter Tabs
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _buildFilterChip('Semua', 'all', selectedFilter, loadTransactions),
                const SizedBox(width: 8),
                _buildFilterChip('Pemasukan', 'income', selectedFilter, loadTransactions),
                const SizedBox(width: 8),
                _buildFilterChip('Pengeluaran', 'expense', selectedFilter, loadTransactions),
                const SizedBox(width: 8),
                _buildFilterChip('Tabungan', 'saving', selectedFilter, loadTransactions),
                const SizedBox(width: 8),
                _buildFilterChip('Investasi', 'investment', selectedFilter, loadTransactions),
              ],
            ),
          ),
          
          // Transaction List
          Expanded(
            child: isLoading.value
                ? const Center(child: CircularProgressIndicator())
                : transactions.value.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.receipt_long, size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text(
                              'Tidak ada transaksi',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: transactions.value.length,
                        itemBuilder: (context, index) {
                          final tx = transactions.value[index];
                          return _buildTransactionCard(
                            context,
                            tx,
                            nf,
                            df,
                            getCategoryName,
                            () => editTransaction(tx),
                            () => deleteTransaction(tx),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSummaryCard(String label, double amount, Color color, NumberFormat nf) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'Rp ${nf.format(amount)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildFilterChip(String label, String value, ValueNotifier<String> selectedFilter, Function() onChanged) {
    final isSelected = selectedFilter.value == value;
    return InkWell(
      onTap: () {
        selectedFilter.value = value;
        onChanged();
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey.shade700,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
  
  Widget _buildTransactionCard(
    BuildContext context,
    TransactionModel tx,
    NumberFormat nf,
    DateFormat df,
    String Function(String?) getCategoryName,
    VoidCallback onEdit,
    VoidCallback onDelete,
  ) {
    Color getTypeColor() {
      if (tx.isIncome) return Colors.green;
      if (tx.type == 'saving' || tx.type == 'saving_out') return Colors.blue;
      if (tx.type == 'investment' || tx.type == 'investment_out') return Colors.purple;
      return Colors.red;
    }
    
    IconData getTypeIcon() {
      if (tx.isIncome) return Icons.arrow_downward;
      if (tx.type == 'saving' || tx.type == 'saving_out') return Icons.savings;
      if (tx.type == 'investment' || tx.type == 'investment_out') return Icons.trending_up;
      return Icons.arrow_upward;
    }
    
    String getTypeLabel() {
      if (tx.isIncome) return 'Pemasukan';
      if (tx.type == 'saving') return 'Tabungan +';
      if (tx.type == 'saving_out') return 'Tabungan -';
      if (tx.type == 'investment') return 'Investasi +';
      if (tx.type == 'investment_out') return 'Investasi -';
      return 'Pengeluaran';
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: getTypeColor().withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            getTypeIcon(),
            color: getTypeColor(),
            size: 24,
          ),
        ),
        title: Text(
          tx.description ?? getCategoryName(tx.category) ?? 'Tidak ada deskripsi',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              '${getTypeLabel()} • ${getCategoryName(tx.category) ?? '-'}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              df.format(tx.date),
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'Rp ${nf.format(tx.amount)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: getTypeColor(),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: onEdit,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.edit,
                      size: 16,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: onDelete,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.delete,
                      size: 16,
                      color: Colors.red.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
