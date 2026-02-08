import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:uuid/uuid.dart';
import 'package:catatan_keuangan_pintar/services/db_service.dart';
import 'package:intl/intl.dart';

class ManualTransactionScreen extends HookWidget {
  const ManualTransactionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uuid = const Uuid();
    final nf = NumberFormat('#,##0', 'id');
    
    final amountCtrl = useTextEditingController();
    final descriptionCtrl = useTextEditingController();
    
    final transactionType = useState('expense'); // income, expense, saving, investment
    final selectedCategory = useState<String?>(null);
    final selectedAccount = useState<String?>('default_cash');
    final selectedGoal = useState<String?>(null);
    final selectedDate = useState(DateTime.now());
    
    final categories = useState<List<Category>>([]);
    final accounts = useState<List<Account>>([]);
    final goals = useState<List<Goal>>([]);
    
    final isLoading = useState(false);

    Future<void> loadData() async {
      try {
        final cats = await DBService.instance.getCategories();
        final accs = await DBService.instance.getAccounts();
        final gls = await DBService.instance.getGoals();
        
        categories.value = cats;
        accounts.value = accs;
        goals.value = gls;
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal memuat data: $e')),
          );
        }
      }
    }

    useEffect(() {
      loadData();
      return null;
    }, const []);

    Future<void> saveTransaction() async {
      final cats = await DBService.instance.getCategories();
      final accs = await DBService.instance.getAccounts();
      final gls = await DBService.instance.getGoals();
      
      categories.value = cats;
      accounts.value = accs;
      goals.value = gls;
    }

    Future<void> _saveTransaction() async {
      final amount = double.tryParse(amountCtrl.text.replaceAll(',', '').replaceAll('.', '')) ?? 0;
      
      if (amount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Jumlah harus lebih dari 0!')),
        );
        return;
      }

      if (selectedCategory.value == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pilih kategori terlebih dahulu!')),
        );
        return;
      }

      isLoading.value = true;

      // determine scope from selected account (if available)
      String txScope = 'personal';
      if (selectedAccount.value != null) {
        final acc = await DBService.instance.getAccount(selectedAccount.value!);
        if (acc != null) txScope = acc.scope;
      }

      final tx = TransactionModel(
        id: uuid.v4(),
        amount: amount,
        currency: 'IDR',
        category: selectedCategory.value,
        description: descriptionCtrl.text.trim().isEmpty ? null : descriptionCtrl.text.trim(),
        date: selectedDate.value,
        createdAt: DateTime.now(),
        isIncome: transactionType.value == 'income',
        type: transactionType.value,
        scope: txScope,
        accountId: selectedAccount.value,
        goalId: selectedGoal.value,
      );

      await DBService.instance.insertTransaction(tx);

      // Update account balance
      if (selectedAccount.value != null) {
        final account = await DBService.instance.getAccount(selectedAccount.value!);
        if (account != null) {
          final newBalance = transactionType.value == 'income'
              ? account.balance + amount
              : account.balance - amount;
          await DBService.instance.updateAccountBalance(account.id, newBalance);
        }
      }

      // Update goal progress (if applicable)
      if (selectedGoal.value != null && (transactionType.value == 'saving' || transactionType.value == 'investment')) {
        await DBService.instance.updateGoalProgress(selectedGoal.value!, amount);
      }

      isLoading.value = false;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transaksi berhasil disimpan!'),
          backgroundColor: Colors.green,
        ),
      );

      // Reset form
      amountCtrl.clear();
      descriptionCtrl.clear();
      selectedCategory.value = null;
      selectedGoal.value = null;
      selectedDate.value = DateTime.now();
    }

    final filteredCategories = categories.value.where((cat) {
      return cat.type == transactionType.value;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tambah Transaksi Manual'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Transaction Type Selector
            const Text(
              'Tipe Transaksi',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                      selectedGoal.value = null;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _TypeChip(
                    label: 'Pengeluaran',
                    icon: Icons.arrow_upward,
                    color: Colors.red,
                    selected: transactionType.value == 'expense',
                    onTap: () {
                      transactionType.value = 'expense';
                      selectedCategory.value = null;
                      selectedGoal.value = null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
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
                const SizedBox(width: 8),
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
            
            const SizedBox(height: 24),
            
            // Amount Input
            const Text(
              'Jumlah',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: amountCtrl,
              decoration: InputDecoration(
                hintText: '0',
                prefixText: 'Rp ',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            
            const SizedBox(height: 24),
            
            // Category Selection
            const Text(
              'Kategori',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: filteredCategories.map((cat) {
                final isSelected = selectedCategory.value == cat.name;
                return ChoiceChip(
                  label: Text(cat.name),
                  selected: isSelected,
                  onSelected: (selected) {
                    selectedCategory.value = selected ? cat.name : null;
                  },
                  selectedColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                );
              }).toList(),
            ),
            
            if (filteredCategories.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Belum ada kategori untuk tipe ini',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            
            const SizedBox(height: 24),
            
            // Account Selection
            const Text(
              'Sumber Dana',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedAccount.value,
                  isExpanded: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  items: accounts.value.map((account) {
                    return DropdownMenuItem(
                      value: account.id,
                      child: Row(
                        children: [
                          Text(account.icon ?? '💰', style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 12),
                          Expanded(child: Text(account.name)),
                          Text(
                            'Rp ${nf.format(account.balance)}',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (value) => selectedAccount.value = value,
                ),
              ),
            ),
            
            // Goal Selection (only for saving/investment)
            if (transactionType.value == 'saving' || transactionType.value == 'investment') ...[
              const SizedBox(height: 24),
              const Text(
                'Target (opsional)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: selectedGoal.value,
                    isExpanded: true,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Tidak ada target'),
                      ),
                      ...goals.value.map((goal) {
                        return DropdownMenuItem(
                          value: goal.id,
                          child: Row(
                            children: [
                              Text(goal.icon ?? '🎯', style: const TextStyle(fontSize: 20)),
                              const SizedBox(width: 12),
                              Expanded(child: Text(goal.name)),
                              Text(
                                '${goal.progressPercentage.toStringAsFixed(0)}%',
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                    onChanged: (value) => selectedGoal.value = value,
                  ),
                ),
              ),
            ],
            
            const SizedBox(height: 24),
            
            // Description
            const Text(
              'Keterangan (opsional)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: descriptionCtrl,
              decoration: InputDecoration(
                hintText: 'Tambahkan keterangan...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              maxLines: 3,
            ),
            
            const SizedBox(height: 24),
            
            // Date Selector
            const Text(
              'Tanggal',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: selectedDate.value,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) {
                  selectedDate.value = picked;
                }
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today, color: Colors.blue),
                    const SizedBox(width: 12),
                    Text(
                      DateFormat('EEEE, dd MMMM yyyy', 'id').format(selectedDate.value),
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Save Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                  onPressed: isLoading.value ? null : saveTransaction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: isLoading.value
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Simpan Transaksi',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.15) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: selected ? color : Colors.grey.shade600,
              size: 28,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: selected ? color : Colors.grey.shade700,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
