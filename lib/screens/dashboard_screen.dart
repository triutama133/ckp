import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:catatan_keuangan_pintar/services/db_service.dart';
import 'package:catatan_keuangan_pintar/services/notification_service.dart';
import 'package:catatan_keuangan_pintar/widgets/insights_widget.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DashboardScreen extends HookWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final nf = NumberFormat('#,##0', 'id');
    final df = DateFormat.yMMMd('id');
    final stats = useState<Map<String, dynamic>?>(null);
    final groups = useState<List<Group>>([]);
    final selectedGroupId = useState<String?>(null);
    final insights = useState<List<SmartInsight>>([]);
    final isLoading = useState(true);
    final selectedPeriod = useState('month'); // day, week, month, year
    final chosenStart = useState<DateTime?>(null);
    final chosenEnd = useState<DateTime?>(null);

    Future<void> loadGroupsAndPrefs() async {
      try {
        final gs = await DBService.instance.getGroups();
        groups.value = gs;
        final prefs = await SharedPreferences.getInstance();
        selectedGroupId.value = prefs.getString('selectedGroupId');
      } catch (e) {
        // Silent fail untuk preferences
      }
    }

    Future<void> loadStats() async {
      isLoading.value = true;
      try {
        final now = DateTime.now();
        DateTime start, end;

        // If user selected a custom range via pickers, use it
        if (chosenStart.value != null && chosenEnd.value != null) {
          start = chosenStart.value!;
          end = chosenEnd.value!;
        } else if (selectedPeriod.value == 'day') {
          start = DateTime(now.year, now.month, now.day);
          end = DateTime(now.year, now.month, now.day, 23, 59, 59);
        } else if (selectedPeriod.value == 'week') {
          start = now.subtract(Duration(days: now.weekday - 1));
          end = start.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));
        } else if (selectedPeriod.value == 'month') {
          start = DateTime(now.year, now.month, 1);
          end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
        } else {
          start = DateTime(now.year, 1, 1);
          end = DateTime(now.year, 12, 31, 23, 59, 59);
        }
      
        final data = await DBService.instance.getDashboardStats(start: start, end: end, groupId: selectedGroupId.value);
        stats.value = data;
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal memuat statistik: $e')),
          );
        }
      }
      isLoading.value = false;
    }

    Future<void> loadInsights() async {
      try {
        final insightsList = await SmartNotificationService.instance.generateInsights();
        insights.value = insightsList;
      } catch (e) {
        // Silent fail untuk insights
      }
    }

    useEffect(() {
      loadGroupsAndPrefs();
      loadStats();
      loadInsights();
      return null;
    }, [selectedPeriod.value, selectedGroupId.value]);

    // Helper that shows a date picker and computes start/end for different periods
    Future<void> _pickPeriodDate(String period) async {
      final now = DateTime.now();
      final initial = chosenStart.value ?? now;
      final picked = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(2000),
        lastDate: DateTime(now.year + 5),
      );

      if (picked == null) return; // user cancelled

      DateTime start;
      DateTime end;

      if (period == 'day') {
        start = DateTime(picked.year, picked.month, picked.day);
        end = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      } else if (period == 'week') {
        start = picked.subtract(Duration(days: picked.weekday - 1));
        end = start.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));
      } else if (period == 'month') {
        start = DateTime(picked.year, picked.month, 1);
        end = DateTime(picked.year, picked.month + 1, 0, 23, 59, 59);
      } else {
        // year
        start = DateTime(picked.year, 1, 1);
        end = DateTime(picked.year, 12, 31, 23, 59, 59);
      }

      chosenStart.value = start;
      chosenEnd.value = end;
      selectedPeriod.value = period;
      await loadStats();
    }

    Future<void> _pickCustomRange() async {
      final now = DateTime.now();
      final initialStart = chosenStart.value ?? DateTime(now.year, now.month, now.day - 7);
      final initialEnd = chosenEnd.value ?? now;
      final initialRange = DateTimeRange(start: initialStart, end: initialEnd);

      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(now.year + 5),
        initialDateRange: initialRange,
      );

      if (picked == null) return;

      chosenStart.value = DateTime(picked.start.year, picked.start.month, picked.start.day);
      chosenEnd.value = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
      selectedPeriod.value = 'custom';
      await loadStats();
    }

    String _rangeLabel() {
      if (chosenStart.value != null && chosenEnd.value != null) {
        return '${df.format(chosenStart.value!)} — ${df.format(chosenEnd.value!)}';
      }

      switch (selectedPeriod.value) {
        case 'day':
          return 'Hari ini';
        case 'week':
          return 'Minggu ini';
        case 'month':
          return 'Bulan ini';
        case 'year':
          return 'Tahun ini';
        default:
          return 'Periode';
      }
    }

    if (isLoading.value || stats.value == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final data = stats.value!;
    final income = (data['income'] as num?)?.toDouble() ?? 0;
    final expense = (data['expense'] as num?)?.toDouble() ?? 0;
    final balance = income - expense;
    final saving = (data['saving'] as num?)?.toDouble() ?? 0;
    final investment = (data['investment'] as num?)?.toDouble() ?? 0;
    final totalBalance = (data['totalBalance'] as num?)?.toDouble() ?? 0;
    
    final topCategories = (data['topExpenseCategories'] as List?) ?? [];
    final goalsProgress = (data['goalsProgress'] as List?) ?? [];

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          await loadStats();
          await loadInsights();
        },
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 120,
              pinned: true,
              backgroundColor: Theme.of(context).colorScheme.primary,
              flexibleSpace: FlexibleSpaceBar(
                title: const Text('Dashboard Keuangan', 
                  style: TextStyle(fontWeight: FontWeight.bold)),
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Theme.of(context).colorScheme.primary,
                        Theme.of(context).colorScheme.secondary,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Period Selector
                    // Group Selector + Period Selector
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String?>(
                                value: selectedGroupId.value,
                                items: [
                                  const DropdownMenuItem(value: null, child: Text('Personal')),
                                  ...groups.value.map((g) => DropdownMenuItem(value: g.id, child: Text(g.name))),
                                ],
                                onChanged: (v) async {
                                  selectedGroupId.value = v;
                                  final prefs = await SharedPreferences.getInstance();
                                  if (v == null) {
                                    await prefs.remove('selectedGroupId');
                                  } else {
                                    await prefs.setString('selectedGroupId', v);
                                  }
                                  await loadStats();
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _PeriodChip(
                            label: 'Hari',
                            selected: selectedPeriod.value == 'day',
                            onTap: () => _pickPeriodDate('day'),
                          ),
                          const SizedBox(width: 8),
                          _PeriodChip(
                            label: 'Minggu',
                            selected: selectedPeriod.value == 'week',
                            onTap: () => _pickPeriodDate('week'),
                          ),
                          const SizedBox(width: 8),
                          _PeriodChip(
                            label: 'Bulan',
                            selected: selectedPeriod.value == 'month',
                            onTap: () => _pickPeriodDate('month'),
                          ),
                          const SizedBox(width: 8),
                          _PeriodChip(
                            label: 'Tahun',
                            selected: selectedPeriod.value == 'year',
                            onTap: () => _pickPeriodDate('year'),
                          ),
                          const SizedBox(width: 8),
                          _PeriodChip(
                            label: 'Kustom',
                            selected: selectedPeriod.value == 'custom',
                            onTap: () => _pickCustomRange(),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  _rangeLabel(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                InkWell(
                                  onTap: _pickCustomRange,
                                  child: Icon(Icons.calendar_today, size: 16, color: Theme.of(context).colorScheme.primary),
                                ),
                                const SizedBox(width: 4),
                                InkWell(
                                  onTap: () async {
                                    chosenStart.value = null;
                                    chosenEnd.value = null;
                                    selectedPeriod.value = 'month';
                                    await loadStats();
                                  },
                                  child: Icon(Icons.refresh, size: 16, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Summary Cards
                    Row(
                      children: [
                        Expanded(
                          child: _SummaryCard(
                            title: 'Pemasukan',
                            amount: income,
                            color: Colors.green,
                            icon: Icons.arrow_downward,
                            nf: nf,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SummaryCard(
                            title: 'Pengeluaran',
                            amount: expense,
                            color: Colors.red,
                            icon: Icons.arrow_upward,
                            nf: nf,
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 12),
                    
                    Row(
                      children: [
                        Expanded(
                          child: _SummaryCard(
                            title: 'Saldo',
                            amount: balance,
                            color: balance >= 0 ? Colors.blue : Colors.orange,
                            icon: Icons.account_balance_wallet,
                            nf: nf,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SummaryCard(
                            title: 'Total Aset',
                            amount: totalBalance,
                            color: Colors.purple,
                            icon: Icons.savings,
                            nf: nf,
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Expense by Category Pie Chart
                    if (topCategories.isNotEmpty) ...[
                      const Text(
                        'Pengeluaran per Kategori',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        height: 220,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: PieChart(
                                PieChartData(
                                  sections: topCategories.asMap().entries.map((entry) {
                                    final idx = entry.key;
                                    final cat = entry.value;
                                    final total = (cat['total'] as num).toDouble();
                                    final colors = [
                                      Colors.red,
                                      Colors.orange,
                                      Colors.yellow.shade700,
                                      Colors.green,
                                      Colors.blue,
                                    ];
                                    return PieChartSectionData(
                                      value: total,
                                      title: '${(total / expense * 100).toStringAsFixed(0)}%',
                                      color: colors[idx % colors.length],
                                      radius: 50,
                                      titleStyle: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    );
                                  }).toList(),
                                  sectionsSpace: 2,
                                  centerSpaceRadius: 40,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 2,
                              child: ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: topCategories.length,
                                itemBuilder: (context, index) {
                                  final cat = topCategories[index];
                                  final category = cat['category'] ?? 'Lainnya';
                                  final colors = [
                                    Colors.red,
                                    Colors.orange,
                                    Colors.yellow.shade700,
                                    Colors.green,
                                    Colors.blue,
                                  ];
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 12,
                                          height: 12,
                                          decoration: BoxDecoration(
                                            color: colors[index % colors.length],
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            category,
                                            style: const TextStyle(fontSize: 11),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    
                    // Goals Progress
                    if (goalsProgress.isNotEmpty) ...[
                      const Text(
                        'Progress Target',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      ...goalsProgress.take(3).map((goal) {
                        final name = goal['name'] as String;
                        final progress = (goal['progress'] as num).toDouble();
                        final current = (goal['current'] as num).toDouble();
                        final target = (goal['target'] as num).toDouble();
                        
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
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
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    '${progress.toStringAsFixed(0)}%',
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: progress / 100,
                                  minHeight: 8,
                                  backgroundColor: Colors.grey.shade200,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Rp ${nf.format(current)} / Rp ${nf.format(target)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 24),
                    ],
                    
                    // Insights & Tips
                    if (insights.value.isNotEmpty) ...[
                      InsightsWidget(insights: insights.value),
                      const SizedBox(height: 24),
                    ],
                    
                    // Quick Stats
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.purple.shade50,
                            Colors.blue.shade50,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          _QuickStatRow(
                            icon: Icons.trending_up,
                            label: 'Tabungan',
                            value: 'Rp ${nf.format(saving)}',
                            color: Colors.green,
                          ),
                          const Divider(height: 20),
                          _QuickStatRow(
                            icon: Icons.show_chart,
                            label: 'Investasi',
                            value: 'Rp ${nf.format(investment)}',
                            color: Colors.blue,
                          ),
                          const Divider(height: 20),
                          _QuickStatRow(
                            icon: Icons.receipt_long,
                            label: 'Total Transaksi',
                            value: '${data['transactionCount']} transaksi',
                            color: Colors.orange,
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Theme.of(context).colorScheme.primary : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.grey.shade700,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final double amount;
  final Color color;
  final IconData icon;
  final NumberFormat nf;

  const _SummaryCard({
    required this.title,
    required this.amount,
    required this.color,
    required this.icon,
    required this.nf,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
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
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Rp ${nf.format(amount)}',
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _QuickStatRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _QuickStatRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
