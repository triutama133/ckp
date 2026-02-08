import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:uuid/uuid.dart';
import 'package:catatan_keuangan_pintar/services/db_service.dart';
import 'package:intl/intl.dart';

class AccountsScreen extends HookWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uuid = const Uuid();
    final nf = NumberFormat('#,##0', 'id');
    final accounts = useState<List<Account>>([]);
    final isLoading = useState(true);

    Future<void> loadAccounts() async {
      isLoading.value = true;
      try {
        final data = await DBService.instance.getAccounts();
        accounts.value = data;
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal memuat akun: $e')),
          );
        }
      }
      isLoading.value = false;
    }

    useEffect(() {
      loadAccounts();
      return null;
    }, const []);

    Future<void> _showAccountEditor({Account? account}) async {
      final nameCtrl = TextEditingController(text: account?.name ?? '');
      final balanceCtrl = TextEditingController(
        text: account != null ? account.balance.toStringAsFixed(0) : '0',
      );
      
      String selectedType = account?.type ?? 'cash';
      String selectedIcon = account?.icon ?? '💵';
      String selectedColor = account?.color ?? '#4CAF50';

      final typeOptions = {
        'cash': 'Tunai',
        'bank': 'Bank',
        'ewallet': 'Dompet Digital',
        'credit_card': 'Kartu Kredit',
      };

      final iconsByType = {
        'cash': ['💵', '💰', '💸', '💴', '💶', '💷'],
        'bank': ['🏦', '🏧', '💳', '💎', '🔐', '📊'],
        'ewallet': ['📱', '💻', '📲', '🌐', '⚡', '🔷'],
        'credit_card': ['💳', '💎', '🎫', '🎴', '📇', '🔖'],
      };

      final colors = [
        '#4CAF50', '#2196F3', '#FF9800', '#9C27B0',
        '#F44336', '#00BCD4', '#FFC107', '#E91E63',
        '#673AB7', '#009688', '#FF5722', '#795548',
      ];

      final result = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(account == null ? 'Tambah Akun Baru' : 'Edit Akun'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Tipe Akun:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: typeOptions.entries.map((entry) {
                      final isSelected = entry.key == selectedType;
                      return ChoiceChip(
                        label: Text(entry.value),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              selectedType = entry.key;
                              selectedIcon = iconsByType[entry.key]!.first;
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Nama Akun',
                      hintText: selectedType == 'bank'
                          ? 'mis: BCA, Mandiri'
                          : selectedType == 'ewallet'
                              ? 'mis: GoPay, OVO'
                              : 'mis: Kas Kecil',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: balanceCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Saldo Awal',
                      border: OutlineInputBorder(),
                      prefixText: 'Rp ',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  const Text('Pilih Icon:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: iconsByType[selectedType]!.map((icon) {
                      final isSelected = icon == selectedIcon;
                      return GestureDetector(
                        onTap: () => setState(() => selectedIcon = icon),
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.blue.shade100 : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(8),
                            border: isSelected
                                ? Border.all(color: Colors.blue, width: 2)
                                : null,
                          ),
                          child: Center(
                            child: Text(icon, style: const TextStyle(fontSize: 24)),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text('Pilih Warna:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: colors.map((colorHex) {
                      final color = Color(int.parse(colorHex.substring(1), radix: 16) + 0xFF000000);
                      final isSelected = colorHex == selectedColor;
                      return GestureDetector(
                        onTap: () => setState(() => selectedColor = colorHex),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(color: Colors.black, width: 3)
                                : null,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Simpan'),
              ),
            ],
          ),
        ),
      );

      if (result == true) {
        final name = nameCtrl.text.trim();
        final balance = double.tryParse(balanceCtrl.text.replaceAll(',', '')) ?? 0;

        if (name.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nama akun harus diisi!')),
          );
          return;
        }

        final newAccount = Account(
          id: account?.id ?? uuid.v4(),
          name: name,
          type: selectedType,
          icon: selectedIcon,
          balance: balance,
          color: selectedColor,
          createdAt: account?.createdAt ?? DateTime.now(),
        );

        if (account == null) {
          await DBService.instance.insertAccount(newAccount);
        } else {
          await DBService.instance.updateAccount(newAccount);
        }

        await loadAccounts();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(account == null ? 'Akun berhasil dibuat!' : 'Akun berhasil diupdate!')),
        );
      }
    }

    Future<void> _adjustBalance(Account account) async {
      final amountCtrl = TextEditingController();
      String adjustType = 'add';

      final result = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text('Sesuaikan Saldo ${account.name}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Saldo saat ini: Rp ${nf.format(account.balance)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Tambah'),
                        selected: adjustType == 'add',
                        onSelected: (selected) {
                          if (selected) setState(() => adjustType = 'add');
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Kurangi'),
                        selected: adjustType == 'subtract',
                        onSelected: (selected) {
                          if (selected) setState(() => adjustType = 'subtract');
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: amountCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Jumlah',
                    border: OutlineInputBorder(),
                    prefixText: 'Rp ',
                  ),
                  keyboardType: TextInputType.number,
                  autofocus: true,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Simpan'),
              ),
            ],
          ),
        ),
      );

      if (result == true) {
        final amount = double.tryParse(amountCtrl.text.replaceAll(',', '')) ?? 0;
        if (amount <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Jumlah harus lebih dari 0!')),
          );
          return;
        }

        final newBalance = adjustType == 'add'
            ? account.balance + amount
            : account.balance - amount;

        await DBService.instance.updateAccountBalance(account.id, newBalance);
        await loadAccounts();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saldo berhasil disesuaikan!')),
        );
      }
    }

    final totalBalance = accounts.value.fold<double>(
      0,
      (sum, account) => sum + account.balance,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Akun & Sumber Dana'),
      ),
      body: isLoading.value
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Total Balance Card
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Theme.of(context).colorScheme.primary,
                        Theme.of(context).colorScheme.secondary,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Total Saldo',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Rp ${nf.format(totalBalance)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${accounts.value.length} akun',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                // Accounts List
                Expanded(
                  child: accounts.value.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.account_balance_wallet,
                                  size: 64, color: Colors.grey.shade300),
                              const SizedBox(height: 16),
                              Text(
                                'Belum ada akun',
                                style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: loadAccounts,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: accounts.value.length,
                            itemBuilder: (context, index) {
                              final account = accounts.value[index];
                              final color = Color(
                                int.parse((account.color ?? '#4CAF50').substring(1), radix: 16) +
                                    0xFF000000,
                              );

                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: InkWell(
                                  onTap: () => _showAccountEditor(account: account),
                                  onLongPress: () => _adjustBalance(account),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 56,
                                          height: 56,
                                          decoration: BoxDecoration(
                                            color: color.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Center(
                                            child: Text(
                                              account.icon ?? '💰',
                                              style: const TextStyle(fontSize: 28),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                account.name,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                account.type == 'bank'
                                                    ? 'Bank'
                                                    : account.type == 'ewallet'
                                                        ? 'E-Wallet'
                                                        : account.type == 'credit_card'
                                                            ? 'Kartu Kredit'
                                                            : 'Tunai',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              'Rp ${nf.format(account.balance)}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                                color: color,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Icon(
                                              Icons.chevron_right,
                                              color: Colors.grey.shade400,
                                              size: 20,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAccountEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Tambah Akun'),
      ),
    );
  }
}
