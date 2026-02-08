import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:uuid/uuid.dart';
import 'package:catatan_keuangan_pintar/services/db_service.dart';
import 'package:intl/intl.dart';

class GoalsScreen extends HookWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uuid = const Uuid();
    final nf = NumberFormat('#,##0', 'id');
    final goals = useState<List<Goal>>([]);
    final isLoading = useState(true);
    final showCompleted = useState(false);

    Future<void> loadGoals() async {
      isLoading.value = true;
      try {
        final data = await DBService.instance.getGoals(activeOnly: !showCompleted.value);
        goals.value = data;
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal memuat target: $e')),
          );
        }
      }
      isLoading.value = false;
    }

    useEffect(() {
      loadGoals();
      return null;
    }, [showCompleted.value]);

    Future<void> _showGoalEditor({Goal? goal}) async {
      final nameCtrl = TextEditingController(text: goal?.name ?? '');
      final descCtrl = TextEditingController(text: goal?.description ?? '');
      final targetCtrl = TextEditingController(
        text: goal != null ? goal.targetAmount.toStringAsFixed(0) : '',
      );
      
      String selectedIcon = goal?.icon ?? '🎯';
      String selectedColor = goal?.color ?? '#2196F3';
      DateTime? targetDate = goal?.targetDate;

      final icons = ['🎯', '🕌', '✈️', '🏠', '🚗', '🎓', '💍', '🏥', '💰', '🌟'];
      final colors = [
        '#2196F3', '#4CAF50', '#FF9800', '#9C27B0',
        '#F44336', '#00BCD4', '#FFC107', '#E91E63',
      ];

      final result = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(goal == null ? 'Buat Target Baru' : 'Edit Target'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nama Target',
                      hintText: 'mis: Haji, Rumah, Mobil',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Deskripsi (opsional)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: targetCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Target Jumlah (Rp)',
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
                    children: icons.map((icon) {
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
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Target Tanggal (opsional)'),
                    subtitle: Text(
                      targetDate != null
                          ? DateFormat('dd MMM yyyy').format(targetDate!)
                          : 'Belum diset',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.calendar_today),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: targetDate ?? DateTime.now().add(const Duration(days: 365)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 3650)),
                        );
                        if (picked != null) {
                          setState(() => targetDate = picked);
                        }
                      },
                    ),
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
        final target = double.tryParse(targetCtrl.text.replaceAll(',', '')) ?? 0;

        if (name.isEmpty || target <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nama dan target harus diisi!')),
          );
          return;
        }

        final newGoal = Goal(
          id: goal?.id ?? uuid.v4(),
          name: name,
          description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
          targetAmount: target,
          currentAmount: goal?.currentAmount ?? 0,
          targetDate: targetDate,
          icon: selectedIcon,
          color: selectedColor,
          createdAt: goal?.createdAt ?? DateTime.now(),
          isActive: goal?.isActive ?? true,
        );

        if (goal == null) {
          await DBService.instance.insertGoal(newGoal);
        } else {
          await DBService.instance.updateGoal(newGoal);
        }

        await loadGoals();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(goal == null ? 'Target berhasil dibuat!' : 'Target berhasil diupdate!')),
        );
      }
    }

    Future<void> _contributeToGoal(Goal goal) async {
      final amountCtrl = TextEditingController();

      final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Setor ke ${goal.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Sisa: Rp ${nf.format(goal.targetAmount - goal.currentAmount)}',
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountCtrl,
                decoration: const InputDecoration(
                  labelText: 'Jumlah Setor',
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
              child: const Text('Setor'),
            ),
          ],
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

        await DBService.instance.updateGoalProgress(goal.id, amount);
        await loadGoals();

        final newAmount = goal.currentAmount + amount;
        if (newAmount >= goal.targetAmount) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🎉 Selamat! Target "${goal.name}" telah tercapai!'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Setoran berhasil dicatat!')),
          );
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Target Keuangan'),
        actions: [
          IconButton(
            icon: Icon(showCompleted.value ? Icons.visibility_off : Icons.visibility),
            onPressed: () => showCompleted.value = !showCompleted.value,
            tooltip: showCompleted.value ? 'Sembunyikan Selesai' : 'Tampilkan Selesai',
          ),
        ],
      ),
      body: isLoading.value
          ? const Center(child: CircularProgressIndicator())
          : goals.value.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.flag, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text(
                        'Belum ada target',
                        style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Buat target pertama Anda!',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: loadGoals,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: goals.value.length,
                    itemBuilder: (context, index) {
                      final goal = goals.value[index];
                      final color = Color(
                        int.parse((goal.color ?? '#2196F3').substring(1), radix: 16) + 0xFF000000,
                      );
                      final progress = goal.progressPercentage;
                      final isCompleted = goal.completedAt != null;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: InkWell(
                          onTap: () => _showGoalEditor(goal: goal),
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 50,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Center(
                                        child: Text(
                                          goal.icon ?? '🎯',
                                          style: const TextStyle(fontSize: 28),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  goal.name,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ),
                                              if (isCompleted)
                                                const Icon(
                                                  Icons.check_circle,
                                                  color: Colors.green,
                                                  size: 20,
                                                ),
                                            ],
                                          ),
                                          if (goal.description != null)
                                            Text(
                                              goal.description!,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      '${progress.toStringAsFixed(0)}%',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                        color: color,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: LinearProgressIndicator(
                                    value: progress / 100,
                                    minHeight: 10,
                                    backgroundColor: Colors.grey.shade200,
                                    valueColor: AlwaysStoppedAnimation<Color>(color),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Rp ${nf.format(goal.currentAmount)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: color,
                                      ),
                                    ),
                                    Text(
                                      'Target: Rp ${nf.format(goal.targetAmount)}',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                if (goal.targetDate != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'Target: ${DateFormat('dd MMM yyyy').format(goal.targetDate!)}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                  ),
                                if (!isCompleted) ...[
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      onPressed: () => _contributeToGoal(goal),
                                      icon: const Icon(Icons.add, size: 18),
                                      label: const Text('Setor'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: color,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showGoalEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Buat Target'),
      ),
    );
  }
}
