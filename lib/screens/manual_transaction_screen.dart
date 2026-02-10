import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:catatan_keuangan_pintar/services/db_service.dart';
import 'package:catatan_keuangan_pintar/services/auto_sync_service.dart';
import 'package:catatan_keuangan_pintar/widgets/hint_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ManualTransactionScreen extends HookWidget {
  const ManualTransactionScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final transactionType = useState<String>('expense');
    final amountCtrl = useTextEditingController();
    final descriptionCtrl = useTextEditingController();
    final selectedCategory = useState<String?>(null);
    final selectedAccount = useState<String?>(null);
    final selectedGroupId = useState<String?>(null);
    final selectedGoal = useState<String?>(null);
    final selectedDate = useState<DateTime>(DateTime.now());
    final isLoading = useState<bool>(false);
    final formattedAmount = useState<String>('0');

    final categories = useState<List<Category>>([]);
    final accounts = useState<List<Account>>([]);
    final goals = useState<List<Goal>>([]);
    final groups = useState<List<Group>>([]);
    final nf = NumberFormat('#,##0', 'id');

    useEffect(() {
      // Load data
      DBService.instance.getCategories().then((c) => categories.value = c);
      DBService.instance.getAccountsWithSavings(groupId: selectedGroupId.value).then((a) => accounts.value = a);
      DBService.instance
          .getGoals(activeOnly: false, groupId: selectedGroupId.value, scope: selectedGroupId.value == null ? 'personal' : 'group')
          .then((g) => goals.value = g);
      DBService.instance.getGroups().then((gs) async {
        groups.value = gs;
        final prefs = await SharedPreferences.getInstance();
        final savedGroupId = prefs.getString('selectedGroupId');
        if (savedGroupId != null && gs.any((g) => g.id == savedGroupId)) {
          selectedGroupId.value = savedGroupId;
        } else {
          if (savedGroupId != null) {
            await prefs.remove('selectedGroupId');
          }
          selectedGroupId.value = null;
        }
      });
      return null;
    }, const []);

    useEffect(() {
      DBService.instance.getAccountsWithSavings(groupId: selectedGroupId.value).then((a) => accounts.value = a);
      DBService.instance
          .getGoals(activeOnly: false, groupId: selectedGroupId.value, scope: selectedGroupId.value == null ? 'personal' : 'group')
          .then((g) => goals.value = g);
      return null;
    }, [selectedGroupId.value]);

    // Update formatted amount when text changes
    void updateFormattedAmount(String value) {
      final raw = value.replaceAll(RegExp(r'[^0-9]'), '');
      if (raw.isEmpty) {
        formattedAmount.value = '0';
      } else {
        final amount = double.tryParse(raw) ?? 0;
        formattedAmount.value = nf.format(amount);
      }
    }

    Future<void> _saveTransaction() async {
      if (isLoading.value) return;
      
      final raw = amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
      final amount = double.tryParse(raw) ?? 0.0;
      
      if (amount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Masukkan jumlah yang valid'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      
      if (selectedCategory.value == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pilih kategori terlebih dahulu'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      
      isLoading.value = true;
      final id = const Uuid().v4();
      
      // Handle savings account withdrawal
      String? actualAccountId = selectedAccount.value;
      String? actualGoalId = selectedGoal.value;
      
      if (selectedAccount.value != null && selectedAccount.value!.startsWith('saving_')) {
        // Extract goal ID from virtual savings account
        final goalId = selectedAccount.value!.replaceFirst('saving_', '');
        actualAccountId = null; // No physical account
        actualGoalId = goalId;   // Link to the goal
      }
      
      final categoryName = categories.value.firstWhere(
        (c) => c.id == selectedCategory.value,
        orElse: () => Category(
          id: selectedCategory.value ?? '',
          name: selectedCategory.value ?? '-',
          type: transactionType.value,
          createdAt: DateTime.now(),
        ),
      ).name;

      final tx = TransactionModel(
        id: id,
        amount: amount,
        currency: 'IDR',
        date: selectedDate.value,
        createdAt: DateTime.now(),
        isIncome: transactionType.value == 'income',
        type: transactionType.value,
        category: categoryName,
        description: descriptionCtrl.text.isEmpty ? null : descriptionCtrl.text,
        accountId: actualAccountId,
        goalId: actualGoalId,
        scope: selectedGroupId.value == null ? 'personal' : 'group',
        groupId: selectedGroupId.value,
      );

      try {
        await DBService.instance.insertTransaction(tx);

        // Auto-sync to cloud (await to catch errors safely)
        try {
          await AutoSyncService.instance.syncTransaction(tx);
        } catch (_) {}

        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Transaksi berhasil disimpan'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        // Reset form instead of popping, since this screen is part of the main tab
        amountCtrl.clear();
        descriptionCtrl.clear();
        formattedAmount.value = '0';
        selectedCategory.value = null;
        selectedAccount.value = null;
        selectedGoal.value = null;
        transactionType.value = 'expense';
        selectedDate.value = DateTime.now();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gagal menyimpan: $e'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } finally {
        if (context.mounted) {
          isLoading.value = false;
        }
      }
    }

    // Filtered lists
    final filteredCategories = categories.value.where((c) => c.type == transactionType.value).toList();
    final filteredGoals = goals.value.where((g) {
      if (selectedGroupId.value == null) return g.groupId == null;
      return g.groupId == selectedGroupId.value;
    }).toList();
    
    // Calculate amount for preview
    final rawAmount = amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    final previewAmount = double.tryParse(rawAmount) ?? 0.0;
    
    // Get selected category name
    String? selectedCategoryName;
    if (selectedCategory.value != null) {
      final cat = categories.value.where((c) => c.id == selectedCategory.value).firstOrNull;
      selectedCategoryName = cat?.name;
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Tambah Transaksi'),
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          HintIcon(
            title: 'Input Transaksi Manual',
            message: 'Gunakan form ini untuk memasukkan transaksi dengan detail lengkap. '
                'Pilih tipe transaksi (Pengeluaran, Pemasukan, Tabungan, Investasi), '
                'kategori, sumber dana, dan opsional link ke target/goal. '
                'Anda juga bisa menambahkan keterangan dan memilih tanggal transaksi.',
            icon: Icons.help_outline,
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Amount Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: transactionType.value == 'income'
                          ? [Colors.green.shade600, Colors.green.shade400]
                          : transactionType.value == 'expense'
                              ? [Colors.red.shade600, Colors.red.shade400]
                              : transactionType.value == 'saving'
                                  ? [Colors.blue.shade600, Colors.blue.shade400]
                                  : [Colors.purple.shade600, Colors.purple.shade400],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: (transactionType.value == 'income'
                                ? Colors.green
                                : transactionType.value == 'expense'
                                    ? Colors.red
                                    : transactionType.value == 'saving'
                                        ? Colors.blue
                                        : Colors.purple)
                            .withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            transactionType.value == 'income'
                                ? Icons.arrow_downward
                                : transactionType.value == 'expense'
                                    ? Icons.arrow_upward
                                    : transactionType.value == 'saving'
                                        ? Icons.savings
                                        : Icons.trending_up,
                            color: Colors.white.withValues(alpha: 0.9),
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            transactionType.value == 'income'
                                ? 'Pemasukan'
                                : transactionType.value == 'expense'
                                    ? 'Pengeluaran'
                                    : transactionType.value == 'saving'
                                        ? 'Tabungan'
                                        : 'Investasi',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: amountCtrl,
                        decoration: const InputDecoration(
                          hintText: '0',
                          hintStyle: TextStyle(
                            color: Colors.white60,
                            fontSize: 40,
                            fontWeight: FontWeight.bold,
                          ),
                          prefixText: 'Rp ',
                          prefixStyle: TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                          border: InputBorder.none,
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                        ),
                        onChanged: updateFormattedAmount,
                      ),
                      Text(
                        formattedAmount.value,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Wallet/Group Selector
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Dompet',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
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
                              onChanged: (v) {
                                selectedGroupId.value = v;
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Transaction Type Selector
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tipe Transaksi',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _TypeChip(
                                label: 'Pemasukan',
                                icon: Icons.arrow_downward,
                                color: Colors.green,
                                selected: transactionType.value == 'income',
                                onTap: () {
                                  transactionType.value = 'income';
                                  selectedCategory.value = null;
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _TypeChip(
                                label: 'Pengeluaran',
                                icon: Icons.arrow_upward,
                                color: Colors.red,
                                selected: transactionType.value == 'expense',
                                onTap: () {
                                  transactionType.value = 'expense';
                                  selectedCategory.value = null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _TypeChip(
                                label: 'Tabungan',
                                icon: Icons.savings,
                                color: Colors.blue,
                                selected: transactionType.value == 'saving',
                                onTap: () {
                                  transactionType.value = 'saving';
                                  selectedCategory.value = null;
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _TypeChip(
                                label: 'Investasi',
                                icon: Icons.trending_up,
                                color: Colors.purple,
                                selected: transactionType.value == 'investment',
                                onTap: () {
                                  transactionType.value = 'investment';
                                  selectedCategory.value = null;
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Category Selection
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Kategori',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (filteredCategories.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline,
                                    color: Colors.orange.shade700),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Belum ada kategori untuk ${transactionType.value}',
                                    style: TextStyle(
                                      color: Colors.orange.shade700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          GestureDetector(
                            onTap: () async {
                              // Show searchable category dialog
                              final selected = await showSearch<Category?>(
                                context: context,
                                delegate: CategorySearchDelegate(
                                  categories: filteredCategories,
                                  selectedId: selectedCategory.value,
                                ),
                              );
                              if (selected != null) {
                                selectedCategory.value = selected.id;
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selectedCategory.value != null
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.grey.shade300,
                                  width: selectedCategory.value != null ? 2 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        selectedCategory.value != null
                                            ? _getCategoryIcon(selectedCategoryName ?? '')
                                            : Icons.category,
                                        size: 20,
                                        color: selectedCategory.value != null
                                            ? Theme.of(context).colorScheme.primary
                                            : Colors.grey.shade600,
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        selectedCategoryName ?? 'Pilih kategori',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: selectedCategory.value != null
                                              ? Theme.of(context).colorScheme.primary
                                              : Colors.grey.shade600,
                                          fontWeight: selectedCategory.value != null
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Icon(
                                    Icons.arrow_drop_down,
                                    color: Colors.grey.shade600,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Account Selection
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Sumber Dana (Opsional)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonHideUnderline(
                          child: DropdownButtonFormField<String?>(
                            value: selectedAccount.value,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              prefixIcon: const Icon(Icons.account_balance),
                            ),
                            items: [
                              const DropdownMenuItem(
                                  value: null, child: Text('Pilih akun (opsional)')),
                              ...accounts.value
                                  .map((a) => DropdownMenuItem(
                                      value: a.id, child: Text(a.name)))
                                  .toList(),
                            ],
                            onChanged: (v) => selectedAccount.value = v,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Goal Selection (if saving/investment)
                if (transactionType.value == 'saving' ||
                    transactionType.value == 'investment') ...[
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Target (Opsional)',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonHideUnderline(
                            child: DropdownButtonFormField<String?>(
                              value: selectedGoal.value,
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: Colors.grey.shade50,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                prefixIcon: const Icon(Icons.track_changes),
                              ),
                              items: [
                                const DropdownMenuItem(
                                    value: null,
                                    child: Text('Tidak ada target')),
                                ...filteredGoals
                                    .map((g) => DropdownMenuItem(
                                        value: g.id, child: Text(g.name)))
                                    .toList(),
                              ],
                              onChanged: (v) => selectedGoal.value = v,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Description
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Keterangan (Opsional)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: descriptionCtrl,
                          decoration: InputDecoration(
                            hintText: 'Tambahkan keterangan...',
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            prefixIcon: const Icon(Icons.note),
                          ),
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Date Selection
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate.value,
                        firstDate: DateTime(2020),
                        lastDate:
                            DateTime.now().add(const Duration(days: 365)),
                        locale: const Locale('id'),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: ColorScheme.light(
                                primary: Theme.of(context).colorScheme.primary,
                                onPrimary: Colors.white,
                                onSurface: Colors.black,
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) selectedDate.value = picked;
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.calendar_today,
                                color: Colors.blue.shade700),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Tanggal',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  DateFormat('EEEE, dd MMMM yyyy', 'id')
                                      .format(selectedDate.value),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios,
                              size: 16, color: Colors.grey.shade400),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Summary Preview (if amount and category selected)
                if (previewAmount > 0 && selectedCategory.value != null)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).colorScheme.primaryContainer,
                          Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              .withValues(alpha: 0.5),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.preview,
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Preview Transaksi',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _SummaryRow(
                          label: 'Tipe',
                          value: transactionType.value == 'income'
                              ? 'Pemasukan'
                              : transactionType.value == 'expense'
                                  ? 'Pengeluaran'
                                  : transactionType.value == 'saving'
                                      ? 'Tabungan'
                                      : 'Investasi',
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                        const Divider(height: 16),
                        _SummaryRow(
                          label: 'Kategori',
                          value: selectedCategoryName ?? '-',
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                        const Divider(height: 16),
                        _SummaryRow(
                          label: 'Jumlah',
                          value: 'Rp ${nf.format(previewAmount)}',
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          isAmount: true,
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 100), // Space for button
              ],
            ),
          ),
          
          // Floating Save Button
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: isLoading.value ? null : _saveTransaction,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: isLoading.value
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle, size: 24),
                              SizedBox(width: 12),
                              Text(
                                'Simpan Transaksi',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(String categoryName) {
    final name = categoryName.toLowerCase();
    if (name.contains('makanan') || name.contains('makan')) return Icons.restaurant;
    if (name.contains('transport')) return Icons.directions_car;
    if (name.contains('belanja')) return Icons.shopping_cart;
    if (name.contains('hiburan')) return Icons.movie;
    if (name.contains('kesehatan')) return Icons.local_hospital;
    if (name.contains('pendidikan')) return Icons.school;
    if (name.contains('tagihan')) return Icons.receipt;
    if (name.contains('gaji')) return Icons.account_balance_wallet;
    if (name.contains('bonus')) return Icons.card_giftcard;
    if (name.contains('investasi')) return Icons.trending_up;
    if (name.contains('tabungan')) return Icons.savings;
    return Icons.category;
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _TypeChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.15) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: selected ? color : Colors.grey.shade600,
              size: 28,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? color : Colors.grey.shade700,
                fontSize: 13,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool isAmount;

  const _SummaryRow({
    required this.label,
    required this.value,
    required this.color,
    this.isAmount = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: color.withValues(alpha: 0.7),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isAmount ? 18 : 14,
            fontWeight: isAmount ? FontWeight.bold : FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

// Category Search Delegate
class CategorySearchDelegate extends SearchDelegate<Category?> {
  final List<Category> categories;
  final String? selectedId;

  CategorySearchDelegate({
    required this.categories,
    this.selectedId,
  });

  @override
  String get searchFieldLabel => 'Cari kategori...';

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return buildSuggestions(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final filteredCategories = query.isEmpty
        ? categories
        : categories.where((cat) => 
            cat.name.toLowerCase().contains(query.toLowerCase())
          ).toList();

    if (filteredCategories.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'Kategori tidak ditemukan',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: filteredCategories.length,
      itemBuilder: (context, index) {
        final cat = filteredCategories[index];
        final isSelected = cat.id == selectedId;
        
        return ListTile(
          leading: Icon(
            _getCategoryIcon(cat.name),
            color: isSelected 
                ? Theme.of(context).colorScheme.primary 
                : Colors.grey.shade700,
          ),
          title: Text(
            cat.name,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected 
                  ? Theme.of(context).colorScheme.primary 
                  : null,
            ),
          ),
          trailing: isSelected 
              ? Icon(
                  Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary,
                )
              : null,
          onTap: () => close(context, cat),
        );
      },
    );
  }

  IconData _getCategoryIcon(String name) {
    final lowerName = name.toLowerCase();
    if (lowerName.contains('makan') || lowerName.contains('food')) {
      return Icons.restaurant;
    } else if (lowerName.contains('transport')) {
      return Icons.directions_car;
    } else if (lowerName.contains('belanja') || lowerName.contains('shop')) {
      return Icons.shopping_bag;
    } else if (lowerName.contains('hiburan') || lowerName.contains('entertainment')) {
      return Icons.movie;
    } else if (lowerName.contains('kesehatan') || lowerName.contains('health')) {
      return Icons.local_hospital;
    } else if (lowerName.contains('pendidikan') || lowerName.contains('education')) {
      return Icons.school;
    } else if (lowerName.contains('tagihan') || lowerName.contains('bill')) {
      return Icons.receipt;
    } else if (lowerName.contains('gaji') || lowerName.contains('salary')) {
      return Icons.attach_money;
    } else if (lowerName.contains('investasi') || lowerName.contains('invest')) {
      return Icons.trending_up;
    } else if (lowerName.contains('tabungan') || lowerName.contains('saving')) {
      return Icons.savings;
    }
    return Icons.category;
  }
}
