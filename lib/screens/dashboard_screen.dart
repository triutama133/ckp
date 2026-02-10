import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:catatan_keuangan_pintar/services/db_service.dart';
import 'package:catatan_keuangan_pintar/services/notification_service.dart';
import 'package:catatan_keuangan_pintar/widgets/insights_widget.dart';
import 'package:catatan_keuangan_pintar/screens/transaction_history_screen.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DashboardScreen extends HookWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final nf = NumberFormat('#,##0', 'id');
    final df = DateFormat.yMMMd('id');
    const locale = Locale('id');
    final stats = useState<Map<String, dynamic>?>(null);
    final previousStats = useState<Map<String, dynamic>?>(null);
    final groups = useState<List<Group>>([]);
    final selectedGroupId = useState<String?>(null);
    final insights = useState<List<SmartInsight>>([]);
    final isLoading = useState(true);
    final selectedPeriod = useState('month'); // day, week, month, year, custom
    final chosenStart = useState<DateTime?>(null);
    final chosenEnd = useState<DateTime?>(null);
    final goldHoldings = useState<List<GoldHolding>>([]);
    final goldTypes = useState<List<GoldType>>([]);
    final goals = useState<List<Goal>>([]);
    final comparisonMode = useState<String?>(null); // null, 'month', 'year'

    Future<void> loadGroupsAndPrefs() async {
      try {
        final gs = await DBService.instance.getGroups();
        groups.value = gs;
        final prefs = await SharedPreferences.getInstance();
        final savedId = prefs.getString('selectedGroupId');
        if (savedId != null && gs.any((g) => g.id == savedId)) {
          selectedGroupId.value = savedId;
        } else {
          selectedGroupId.value = null;
          await prefs.remove('selectedGroupId');
        }
      } catch (e) {
        // Silent fail
      }
    }

    Future<void> loadGoldData() async {
      try {
        final holdings = await DBService.instance.getGoldHoldings(groupId: selectedGroupId.value);
        final types = await DBService.instance.getGoldTypes();
        goldHoldings.value = holdings;
        goldTypes.value = types;
      } catch (e) {
        // Silent fail
      }
    }

    Future<void> loadGoals() async {
      try {
        final goalsList = await DBService.instance.getGoals(activeOnly: true);
        goals.value = goalsList;
      } catch (e) {
        // Silent fail
      }
    }

    Future<void> loadComparisonStats(DateTime currentStart, DateTime currentEnd) async {
      try {
        if (comparisonMode.value == 'month') {
          // Compare current month vs previous month
          final now = DateTime.now();
          final prevStart = DateTime(now.year, now.month - 1, 1);
          final prevEnd = DateTime(now.year, now.month, 0, 23, 59, 59);
          final data = await DBService.instance.getDashboardStats(
            start: prevStart,
            end: prevEnd,
            groupId: selectedGroupId.value,
          );
          previousStats.value = data;
        } else if (comparisonMode.value == 'year') {
          // Compare current year vs previous year
          final now = DateTime.now();
          final prevStart = DateTime(now.year - 1, 1, 1);
          final prevEnd = DateTime(now.year - 1, 12, 31, 23, 59, 59);
          final data = await DBService.instance.getDashboardStats(
            start: prevStart,
            end: prevEnd,
            groupId: selectedGroupId.value,
          );
          previousStats.value = data;
        } else {
          // Default: compare with same-length previous period
          final periodLength = currentEnd.difference(currentStart).inDays;
          final previousStart = currentStart.subtract(Duration(days: periodLength + 1));
          final previousEnd = currentStart.subtract(const Duration(days: 1));
          
          final data = await DBService.instance.getDashboardStats(
            start: previousStart,
            end: previousEnd,
            groupId: selectedGroupId.value,
          );
          previousStats.value = data;
        }
      } catch (e) {
        previousStats.value = null;
      }
    }

    Future<void> loadStats() async {
      isLoading.value = true;
      try {
        final now = DateTime.now();
        DateTime start, end;

        if (chosenStart.value != null && chosenEnd.value != null) {
          start = chosenStart.value!;
          end = chosenEnd.value!;
        } else if (comparisonMode.value == 'month') {
          // For month comparison, show current month
          start = DateTime(now.year, now.month, 1);
          end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
        } else if (comparisonMode.value == 'year') {
          // For year comparison, show current year
          start = DateTime(now.year, 1, 1);
          end = DateTime(now.year, 12, 31, 23, 59, 59);
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
      
        final data = await DBService.instance.getDashboardStats(
          start: start,
          end: end,
          groupId: selectedGroupId.value,
        );
        stats.value = data;
        
        // Load previous period for comparison
        await loadComparisonStats(start, end);
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
        // Silent fail
      }
    }

    useEffect(() {
      loadGroupsAndPrefs();
      loadStats();
      loadInsights();
      loadGoldData();
      loadGoals();
      return null;
    }, [selectedPeriod.value, selectedGroupId.value, comparisonMode.value]);

    Future<void> _pickPeriodDate(String period) async {
      // Simply set the period and clear custom dates — loadStats will compute the range
      chosenStart.value = null;
      chosenEnd.value = null;
      comparisonMode.value = null;
      selectedPeriod.value = period;
    }

    Future<void> _pickCustomRange() async {
      final now = DateTime.now();
      
      // Show comprehensive period selection dialog
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Pilih Periode'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // === Quick Presets ===
                const Text('Periode Cepat', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 8),
                _PeriodDialogOption(
                  icon: Icons.today,
                  label: 'Hari Ini',
                  onTap: () => Navigator.of(ctx).pop('today'),
                ),
                _PeriodDialogOption(
                  icon: Icons.view_week,
                  label: 'Minggu Ini',
                  onTap: () => Navigator.of(ctx).pop('week'),
                ),
                _PeriodDialogOption(
                  icon: Icons.view_week_outlined,
                  label: 'Minggu Lalu',
                  onTap: () => Navigator.of(ctx).pop('last_week'),
                ),
                _PeriodDialogOption(
                  icon: Icons.calendar_month,
                  label: 'Bulan Ini',
                  onTap: () => Navigator.of(ctx).pop('month'),
                ),
                _PeriodDialogOption(
                  icon: Icons.calendar_month_outlined,
                  label: 'Bulan Lalu',
                  onTap: () => Navigator.of(ctx).pop('last_month'),
                ),
                _PeriodDialogOption(
                  icon: Icons.calendar_today,
                  label: 'Tahun Ini',
                  onTap: () => Navigator.of(ctx).pop('year'),
                ),
                
                const Divider(height: 24),
                
                // === Comparison Modes ===
                const Text('Bandingkan Periode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 8),
                _PeriodDialogOption(
                  icon: Icons.compare_arrows,
                  label: 'Bulan Ini vs Bulan Lalu',
                  subtitle: 'Perbandingan pendapatan, pengeluaran, tabungan',
                  onTap: () => Navigator.of(ctx).pop('compare_month'),
                ),
                _PeriodDialogOption(
                  icon: Icons.compare_arrows,
                  label: 'Tahun Ini vs Tahun Lalu',
                  subtitle: 'Perbandingan tahunan',
                  onTap: () => Navigator.of(ctx).pop('compare_year'),
                ),
                
                const Divider(height: 24),
                
                // === Custom Range ===
                _PeriodDialogOption(
                  icon: Icons.date_range,
                  label: 'Pilih Tanggal Custom',
                  onTap: () => Navigator.of(ctx).pop('custom'),
                ),
              ],
            ),
          ),
        ),
      );

      if (choice == null || !context.mounted) return;

      DateTime start, end;

      switch (choice) {
        case 'today':
          chosenStart.value = null;
          chosenEnd.value = null;
          comparisonMode.value = null;
          selectedPeriod.value = 'day';
          return;
        case 'week':
          chosenStart.value = null;
          chosenEnd.value = null;
          comparisonMode.value = null;
          selectedPeriod.value = 'week';
          return;
        case 'last_week':
          final weekStart = now.subtract(Duration(days: now.weekday - 1));
          start = weekStart.subtract(const Duration(days: 7));
          end = weekStart.subtract(const Duration(seconds: 1));
          break;
        case 'month':
          chosenStart.value = null;
          chosenEnd.value = null;
          comparisonMode.value = null;
          selectedPeriod.value = 'month';
          return;
        case 'last_month':
          start = DateTime(now.year, now.month - 1, 1);
          end = DateTime(now.year, now.month, 0, 23, 59, 59);
          break;
        case 'year':
          chosenStart.value = null;
          chosenEnd.value = null;
          comparisonMode.value = null;
          selectedPeriod.value = 'year';
          return;
        case 'compare_month':
          chosenStart.value = null;
          chosenEnd.value = null;
          comparisonMode.value = 'month';
          selectedPeriod.value = 'month';
          return;
        case 'compare_year':
          chosenStart.value = null;
          chosenEnd.value = null;
          comparisonMode.value = 'year';
          selectedPeriod.value = 'year';
          return;
        case 'custom':
          final initialStart = chosenStart.value ?? DateTime(now.year, now.month, now.day - 7);
          final initialEnd = chosenEnd.value ?? now;
          final initialRange = DateTimeRange(start: initialStart, end: initialEnd);

          final picked = await showDateRangePicker(
            context: context,
            firstDate: DateTime(2000),
            lastDate: DateTime(now.year + 5),
            initialDateRange: initialRange,
            locale: locale,
          );

          if (picked == null) return;
          start = DateTime(picked.start.year, picked.start.month, picked.start.day);
          end = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
          break;
        default:
          return;
      }

      chosenStart.value = start;
      chosenEnd.value = end;
      comparisonMode.value = null;
      selectedPeriod.value = 'custom';
      await loadStats();
    }

    String _rangeLabel() {
      if (comparisonMode.value == 'month') {
        return 'Bulan Ini vs Lalu';
      }
      if (comparisonMode.value == 'year') {
        return 'Tahun Ini vs Lalu';
      }
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

    // Generate AI insights with international standards and comparisons
    List<Map<String, dynamic>> _generateInsights(
      Map<String, dynamic> data, 
      double income, 
      double expense,
      Map<String, dynamic>? previousData,
    ) {
      final insights = <Map<String, dynamic>>[];
      final saving = (data['saving'] as num?)?.toDouble() ?? 0;
      final savingRate = income > 0 ? (saving / income * 100) : 0;
      final totalBalance = (data['totalBalance'] as num?)?.toDouble() ?? 0;
      
      // === COMPARISON INSIGHTS ===
      if (previousData != null) {
        final prevIncome = (previousData['income'] as num?)?.toDouble() ?? 0;
        final prevExpense = (previousData['expense'] as num?)?.toDouble() ?? 0;
        final prevSaving = (previousData['saving'] as num?)?.toDouble() ?? 0;
        
        // Income comparison
        if (prevIncome > 0) {
          final incomeChange = ((income - prevIncome) / prevIncome * 100);
          if (incomeChange > 5) {
            insights.add({
              'icon': Icons.trending_up,
              'color': Colors.green,
              'title': 'Pendapatan Naik!',
              'message': 'Pendapatan naik ${incomeChange.toStringAsFixed(1)}% dari periode sebelumnya. Pertahankan!',
            });
          } else if (incomeChange < -5) {
            insights.add({
              'icon': Icons.trending_down,
              'color': Colors.orange,
              'title': 'Pendapatan Turun',
              'message': 'Pendapatan turun ${incomeChange.abs().toStringAsFixed(1)}% dari periode sebelumnya.',
            });
          }
        }
        
        // Expense comparison
        if (prevExpense > 0) {
          final expenseChange = ((expense - prevExpense) / prevExpense * 100);
          if (expenseChange > 10) {
            insights.add({
              'icon': Icons.warning_amber,
              'color': Colors.red,
              'title': 'Pengeluaran Meningkat!',
              'message': 'Pengeluaran naik ${expenseChange.toStringAsFixed(1)}% dari periode sebelumnya. Cek pengeluaran Anda!',
            });
          } else if (expenseChange < -5) {
            insights.add({
              'icon': Icons.check_circle,
              'color': Colors.green,
              'title': 'Pengeluaran Terkendali',
              'message': 'Pengeluaran turun ${expenseChange.abs().toStringAsFixed(1)}% dari periode sebelumnya. Bagus!',
            });
          }
        }
        
        // Saving comparison
        if (prevSaving > 0) {
          final savingChange = ((saving - prevSaving) / prevSaving * 100);
          if (savingChange > 10) {
            insights.add({
              'icon': Icons.savings,
              'color': Colors.green,
              'title': 'Tabungan Meningkat!',
              'message': 'Tabungan naik ${savingChange.toStringAsFixed(1)}% dari periode sebelumnya. Luar biasa!',
            });
          }
        }
      }
      
      // === INTERNATIONAL FINANCIAL HEALTH STANDARDS ===
      
      // 1. 50/30/20 Rule (Needs/Wants/Savings)
      if (income > 0) {
        final savingsPercentage = (saving / income * 100);
        if (savingsPercentage < 20) {
          insights.add({
            'icon': Icons.pie_chart_outline,
            'color': Colors.orange,
            'title': '50/30/20 Rule',
            'message': 'Standar internasional: 50% kebutuhan, 30% keinginan, 20% tabungan. Anda menabung ${savingsPercentage.toStringAsFixed(1)}%. Target: 20%.',
          });
        } else {
          insights.add({
            'icon': Icons.pie_chart,
            'color': Colors.green,
            'title': '50/30/20 Rule ✓',
            'message': 'Anda menabung ${savingsPercentage.toStringAsFixed(1)}% - memenuhi standar 50/30/20! Pertahankan!',
          });
        }
      }
      
      // 2. Emergency Fund (3-6 months of average monthly income)
      final monthlyIncome = income; // Current period income (assumed monthly)
      final emergencyFundMonths = monthlyIncome > 0 ? (totalBalance / monthlyIncome) : 0;
      if (emergencyFundMonths < 3) {
        insights.add({
          'icon': Icons.emergency,
          'color': Colors.red,
          'title': 'Dana Darurat Kurang!',
          'message': 'Dana darurat Anda hanya cukup untuk ${emergencyFundMonths.toStringAsFixed(1)} bulan pendapatan. Standar: 3-6x rata-rata pendapatan bulanan (Rp ${nf.format(monthlyIncome * 3)} - ${nf.format(monthlyIncome * 6)}).',
        });
      } else if (emergencyFundMonths < 6) {
        insights.add({
          'icon': Icons.shield,
          'color': Colors.blue,
          'title': 'Dana Darurat Cukup',
          'message': 'Dana darurat Anda cukup untuk ${emergencyFundMonths.toStringAsFixed(1)} bulan pendapatan. Tingkatkan ke 6 bulan untuk keamanan optimal.',
        });
      } else {
        insights.add({
          'icon': Icons.verified_user,
          'color': Colors.green,
          'title': 'Dana Darurat Aman!',
          'message': 'Dana darurat Anda cukup untuk ${emergencyFundMonths.toStringAsFixed(1)} bulan pendapatan. Sangat baik!',
        });
      }
      
      // 3. Savings Rate Assessment
      if (income > 0 && expense <= income) {
        // Only show saving rate insights when not in deficit
        if (savingRate > 30) {
          insights.add({
            'icon': Icons.star,
            'color': Colors.amber,
            'title': 'Saving Rate Luar Biasa!',
            'message': 'Anda menabung ${savingRate.toStringAsFixed(1)}% dari pendapatan. Jauh di atas rata-rata global (15-20%)!',
          });
        } else if (savingRate > 20) {
          insights.add({
            'icon': Icons.celebration,
            'color': Colors.green,
            'title': 'Saving Rate Hebat!',
            'message': 'Anda menabung ${savingRate.toStringAsFixed(1)}% dari pendapatan. Memenuhi standar internasional!',
          });
        } else if (savingRate > 10) {
          insights.add({
            'icon': Icons.thumb_up,
            'color': Colors.blue,
            'title': 'Saving Rate Bagus',
            'message': 'Anda menabung ${savingRate.toStringAsFixed(1)}%. Target ideal: 20% (standar internasional).',
          });
        } else if (savingRate > 0) {
          insights.add({
            'icon': Icons.warning,
            'color': Colors.orange,
            'title': 'Tingkatkan Saving Rate',
            'message': 'Saving rate hanya ${savingRate.toStringAsFixed(1)}%. Standar minimum: 10-15%.',
          });
        } else {
          insights.add({
            'icon': Icons.info_outline,
            'color': Colors.blue,
            'title': 'Belum Ada Tabungan',
            'message': 'Pendapatan masih lebih besar dari pengeluaran, tapi belum ada alokasi tabungan. Mulai sisihkan sebagian pendapatan!',
          });
        }
      } else if (income > 0 && expense > income) {
        insights.add({
          'icon': Icons.error,
          'color': Colors.red,
          'title': 'Pengeluaran Melebihi!',
          'message': 'Pengeluaran (Rp ${nf.format(expense)}) melebihi pemasukan (Rp ${nf.format(income)}). Segera evaluasi keuangan Anda.',
        });
      }
      
      // 4. Category insight
      final topCats = (data['topExpenseCategories'] as List?) ?? [];
      if (topCats.isNotEmpty) {
        final top = topCats[0] as Map;
        final catName = top['category'] ?? 'Tidak diketahui';
        final catAmount = (top['total'] as num?)?.toDouble() ?? 0;
        final percentage = expense > 0 ? (catAmount / expense * 100) : 0;
        
        insights.add({
          'icon': Icons.analytics,
          'color': Colors.purple,
          'title': 'Kategori Terbesar',
          'message': '$catName menghabiskan ${percentage.toStringAsFixed(0)}% (Rp ${nf.format(catAmount)}) dari total pengeluaran.',
        });
      }
      
      // 5. Balance trend
      if (income > expense) {
        final surplus = income - expense;
        final surplusRate = (surplus / income * 100);
        insights.add({
          'icon': Icons.trending_up,
          'color': Colors.green,
          'title': 'Surplus ${surplusRate.toStringAsFixed(0)}%',
          'message': 'Anda memiliki surplus Rp ${nf.format(surplus)}. Alokasikan untuk investasi atau dana darurat.',
        });
      } else if (expense > income) {
        final deficit = expense - income;
        insights.add({
          'icon': Icons.trending_down,
          'color': Colors.red,
          'title': 'Defisit Keuangan',
          'message': 'Defisit Rp ${nf.format(deficit)}. Kurangi pengeluaran atau tingkatkan pendapatan.',
        });
      }
      
      return insights;
    }

    if (stats.value == null) {
      return Scaffold(
        backgroundColor: Colors.grey.shade50,
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Memuat dashboard...'),
            ],
          ),
        ),
      );
    }

    final data = stats.value!;
    final income = (data['income'] as num?)?.toDouble() ?? 0;
    final expense = (data['expense'] as num?)?.toDouble() ?? 0;
    final balance = income - expense;
    final saving = (data['saving'] as num?)?.toDouble() ?? 0;
    final investment = (data['investment'] as num?)?.toDouble() ?? 0;
    final totalBalance = (data['totalBalance'] as num?)?.toDouble() ?? 0;
    
    // Use transaction-derived net balance (income - expense) as cash balance
    // since account balances are not updated by transactions
    final cashBalance = balance > 0 ? balance : totalBalance;
    
    final topCategories = (data['topExpenseCategories'] as List?) ?? [];
    final goldSummary = (data['goldSummary'] as Map?) ?? {};
    final goldValue = (goldSummary['value'] as num?)?.toDouble() ?? 0;
    final goldGrams = (goldSummary['grams'] as num?)?.toDouble() ?? 0;
    
    // Calculate total gold value from holdings
    double totalGoldValue = 0;
    double totalGoldGrams = 0;
    for (final holding in goldHoldings.value) {
      final type = goldTypes.value.firstWhere(
        (t) => t.id == holding.typeId,
        orElse: () => GoldType(id: '', name: '', pricePerGram: 0, createdAt: DateTime.now()),
      );
      totalGoldGrams += holding.grams;
      totalGoldValue +=  holding.grams * type.pricePerGram;
    }
    
    // Total portfolio = cash balance (net from transactions) + savings + investments + gold value
    final totalPortfolio = cashBalance + saving + investment + totalGoldValue;
    
    String scopeLabel = 'Personal';
    if (selectedGroupId.value != null) {
      String? groupName;
      for (final g in groups.value) {
        if (g.id == selectedGroupId.value) {
          groupName = g.name;
          break;
        }
      }
      scopeLabel = 'Grup${groupName != null ? ': $groupName' : ''}';
    }
    
    final aiInsights = _generateInsights(data, income, expense, previousStats.value);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            loadGroupsAndPrefs(),
            loadStats(),
            loadInsights(),
            loadGoldData(),
            loadGoals(),
          ]);
        },
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: CustomScrollView(
            key: ValueKey('${selectedGroupId.value}-${selectedPeriod.value}-${comparisonMode.value}'),
            slivers: [
            // AppBar with gradient
            SliverAppBar(
              expandedHeight: 100,
              pinned: true,
              backgroundColor: Theme.of(context).colorScheme.primary,
              flexibleSpace: FlexibleSpaceBar(
                title: const Text(
                  'Dashboard',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
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
                    // Filter Controls
                    _buildFilterControls(
                      context,
                      selectedGroupId,
                      groups,
                      selectedPeriod,
                      _pickPeriodDate,
                      _pickCustomRange,
                      _rangeLabel,
                      loadStats,
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Portfolio Overview Card - HERO SECTION
                    _buildPortfolioOverviewCard(
                      context,
                      totalPortfolio,
                      cashBalance,
                      totalGoldValue,
                      totalGoldGrams,
                      income,
                      expense,
                      saving,
                      nf,
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Quick Stats Grid
                    _buildQuickStatsGrid(income, expense, saving, investment, balance, totalGoldValue, totalGoldGrams, nf),
                    
                    const SizedBox(height: 12),
                    
                    // Transaction History Shortcut
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const TransactionHistoryScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.history),
                      label: const Text('Lihat Riwayat Transaksi'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Comparison with Previous Period
                    if (previousStats.value != null) ...[
                      _buildSectionHeader(
                        comparisonMode.value == 'month'
                            ? 'Bulan Ini vs Bulan Lalu'
                            : comparisonMode.value == 'year'
                                ? 'Tahun Ini vs Tahun Lalu'
                                : 'Perbandingan Periode',
                        Icons.compare_arrows,
                      ),
                      const SizedBox(height: 12),
                      _buildComparisonCard(
                        context,
                        data,
                        previousStats.value!,
                        income,
                        expense,
                        saving,
                        nf,
                      ),
                      const SizedBox(height: 20),
                    ],
                    
                    // AI Insights Section
                    if (aiInsights.isNotEmpty) ...[
                      _buildSectionHeader('Smart Insights', Icons.lightbulb),
                      const SizedBox(height: 12),
                      ...aiInsights.map((insight) => _buildInsightCard(
                        context,
                        insight['icon'] as IconData,
                        insight['color'] as Color,
                        insight['title'] as String,
                        insight['message'] as String,
                      )),
                      const SizedBox(height: 20),
                    ],
                    
                    // Gold Portfolio Card
                    if (goldHoldings.value.isNotEmpty) ...[
                      _buildSectionHeader('Portfolio Emas', Icons.stars),
                      const SizedBox(height: 12),
                      _buildGoldPortfolioCard(
                        context,
                        goldHoldings.value,
                        goldTypes.value,
                        totalGoldValue,
                        totalGoldGrams,
                        nf,
                      ),
                      const SizedBox(height: 20),
                    ],
                    
                    // Goals Progress
                    if (goals.value.isNotEmpty) ...[
                      _buildSectionHeader('Progress Tujuan', Icons.track_changes),
                      const SizedBox(height: 12),
                      ...goals.value.map((goal) => _buildGoalProgressCard(
                        context,
                        goal,
                        nf,
                      )),
                      const SizedBox(height: 20),
                    ],
                    
                    // Category Breakdown Pie Chart
                    if (topCategories.isNotEmpty) ...[
                      _buildSectionHeader('📊 Kategori Pengeluaran', Icons.pie_chart),
                      const SizedBox(height: 12),
                      _buildCategoryPieChart(topCategories, expense, nf),
                      const SizedBox(height: 20),
                    ],
                    
                    const SizedBox(height: 60),
                  ],
                ),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper: Build Filter Controls
  Widget _buildFilterControls(
    BuildContext context,
    ValueNotifier<String?> selectedGroupId,
    ValueNotifier<List<Group>> groups,
    ValueNotifier<String> selectedPeriod,
    Function(String) pickPeriodDate,
    Function() pickCustomRange,
    String Function() rangeLabel,
    Function() loadStats,
  ) {
    return Column(
      children: [
        // Group Selector
        Container(
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
              icon: const Icon(Icons.arrow_drop_down),
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
                await loadStats();
              },
            ),
          ),
        ),
        
        const SizedBox(height: 12),
        
        // Period Selector — single button that opens the dialog
        InkWell(
          onTap: () => pickCustomRange(),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
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
                Icon(Icons.calendar_month, color: Theme.of(context).colorScheme.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    rangeLabel(),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                Icon(Icons.arrow_drop_down, color: Theme.of(context).colorScheme.primary),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Helper: Build Portfolio Overview Card
  Widget _buildPortfolioOverviewCard(
    BuildContext context,
    double totalPortfolio,
    double cashBalance,
    double goldValue,
    double goldGrams,
    double income,
    double expense,
    double saving,
    NumberFormat nf,
  ) {
    final savingRate = income > 0 ? (saving / income * 100) : 0;
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF667eea),
            const Color(0xFF764ba2),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF667eea).withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.account_balance_wallet,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Total Portfolio',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          Text(
            'Rp ${nf.format(totalPortfolio)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Breakdown
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _buildPortfolioRow(
                  Icons.account_balance,
                  'Cash Balance',
                  'Rp ${nf.format(cashBalance)}',
                  percentage: cashBalance / (totalPortfolio > 0 ? totalPortfolio : 1) * 100,
                ),
                if (goldValue > 0) ...[
                  const SizedBox(height: 12),
                  Divider(color: Colors.white.withValues(alpha: 0.3), height: 1),
                  const SizedBox(height: 12),
                  _buildPortfolioRow(
                    Icons.stars,
                    'Emas (${goldGrams.toStringAsFixed(2)}g)',
                    'Rp ${nf.format(goldValue)}',
                    percentage: goldValue / (totalPortfolio > 0 ? totalPortfolio : 1) * 100,
                  ),
                ],
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Saving Rate Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: savingRate > 20
                  ? Colors.green.withValues(alpha: 0.3)
                  : savingRate > 10
                      ? Colors.blue.withValues(alpha: 0.3)
                      : Colors.orange.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  savingRate > 20
                      ? Icons.trending_up
                      : savingRate > 0
                          ? Icons.show_chart
                          : Icons.trending_down,
                  color: Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  'Saving Rate: ${savingRate.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortfolioRow(IconData icon, String label, String value, {required double percentage}) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${percentage.toStringAsFixed(0)}%',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Helper: Build Quick Stats Grid
  Widget _buildQuickStatsGrid(
    double income,
    double expense,
    double saving,
    double investment,
    double balance,
    double goldValue,
    double goldGrams,
    NumberFormat nf,
  ) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: [
        _QuickStatCard(
          icon: Icons.arrow_downward,
          label: 'Pemasukan',
          value: 'Rp ${nf.format(income)}',
          color: Colors.green,
          trend: income > 0 ? '+' : '',
        ),
        _QuickStatCard(
          icon: Icons.arrow_upward,
          label: 'Pengeluaran',
          value: 'Rp ${nf.format(expense)}',
          color: Colors.red,
          trend: expense > 0 ? '-' : '',
        ),
        _QuickStatCard(
          icon: Icons.savings,
          label: 'Tabungan',
          value: 'Rp ${nf.format(saving)}',
          color: Colors.blue,
        ),
        _QuickStatCard(
          icon: Icons.trending_up,
          label: 'Investasi',
          value: 'Rp ${nf.format(investment)}',
          color: Colors.purple,
        ),
        _QuickStatCard(
          icon: Icons.stars,
          label: 'Emas (${goldGrams.toStringAsFixed(2)}g)',
          value: 'Rp ${nf.format(goldValue)}',
          color: Colors.amber.shade700,
        ),
        _QuickStatCard(
          icon: Icons.account_balance,
          label: 'Saldo Bersih',
          value: 'Rp ${nf.format(balance)}',
          color: balance >= 0 ? Colors.teal : Colors.red.shade700,
        ),
      ],
    );
  }

  // Helper: Build Section Header
  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey.shade700),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade800,
          ),
        ),
      ],
    );
  }

  // Helper: Build Insight Card
  Widget _buildInsightCard(
    BuildContext context,
    IconData icon,
    Color color,
    String title,
    String message,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0,4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper: Build Comparison Card
  Widget _buildComparisonCard(
    BuildContext context,
    Map<String, dynamic> currentData,
    Map<String, dynamic> previousData,
    double currentIncome,
    double currentExpense,
    double currentSaving,
    NumberFormat nf,
  ) {
    final prevIncome = (previousData['income'] as num?)?.toDouble() ?? 0;
    final prevExpense = (previousData['expense'] as num?)?.toDouble() ?? 0;
    final prevSaving = (previousData['saving'] as num?)?.toDouble() ?? 0;
    
    final incomeChange = prevIncome > 0 ? ((currentIncome - prevIncome) / prevIncome * 100).toDouble() : 0.0;
    final expenseChange = prevExpense > 0 ? ((currentExpense - prevExpense) / prevExpense * 100).toDouble() : 0.0;
    final savingChange = prevSaving > 0 ? ((currentSaving - prevSaving) / prevSaving * 100).toDouble() : 0.0;
    
    return Container(
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Income Comparison
          _buildComparisonRow(
            'Pendapatan',
            Icons.arrow_downward,
            Colors.green,
            currentIncome,
            prevIncome,
            incomeChange,
            nf,
          ),
          const Divider(height: 24),
          
          // Expense Comparison
          _buildComparisonRow(
            'Pengeluaran',
            Icons.arrow_upward,
            Colors.red,
            currentExpense,
            prevExpense,
            expenseChange,
            nf,
          ),
          const Divider(height: 24),
          
          // Saving Comparison
          _buildComparisonRow(
            'Tabungan',
            Icons.savings,
            Colors.blue,
            currentSaving,
            prevSaving,
            savingChange,
            nf,
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonRow(
    String label,
    IconData icon,
    Color color,
    double current,
    double previous,
    double changePercent,
    NumberFormat nf,
  ) {
    final isPositive = changePercent > 0;
    final isNegative = changePercent < 0;
    final changeColor = isPositive ? Colors.green : (isNegative ? Colors.red : Colors.grey);
    
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Rp ${nf.format(current)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: changeColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isPositive ? Icons.trending_up : (isNegative ? Icons.trending_down : Icons.remove),
                color: changeColor,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                '${changePercent >= 0 ? '+' : ''}${changePercent.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: changeColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Helper: Build Gold Portfolio Card
  Widget _buildGoldPortfolioCard(
    BuildContext context,
    List<GoldHolding> holdings,
    List<GoldType> types,
    double totalValue,
    double totalGrams,
    NumberFormat nf,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.amber.shade600, Colors.amber.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withValues(alpha: 0.3),
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
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.stars, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Portfolio Emas',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Gram',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${totalGrams.toStringAsFixed(2)} g',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Nilai Sekarang',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Rp ${nf.format(totalValue)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Holdings breakdown
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: holdings.take(3).map((holding) {
                final type = types.firstWhere(
                  (t) => t.id == holding.typeId,
                  orElse: () => GoldType(
                    id: '',
                    name: 'Unknown',
                    pricePerGram: 0,
                    createdAt: DateTime.now(),
                  ),
                );
                final value = holding.grams * type.pricePerGram;
                
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${type.name} (${holding.grams.toStringAsFixed(2)}g)',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        'Rp ${nf.format(value)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // Helper: Build Goal Progress Card
  Widget _buildGoalProgressCard(
    BuildContext context,
    Goal goal,
    NumberFormat nf,
  ) {
    final progress = goal.targetAmount > 0 ? goal.currentAmount / goal.targetAmount : 0;
    final remaining = goal.targetAmount - goal.currentAmount;
    final daysRemaining = goal.targetDate?.difference(DateTime.now()).inDays ?? 0;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
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
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.flag, color: Colors.blue.shade700, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      goal.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (goal.targetDate != null)
                      Text(
                        '${daysRemaining > 0 ? '$daysRemaining hari lagi' : 'Target terlewat'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: daysRemaining > 0 ? Colors.green : Colors.red,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                '${(progress * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: progress >= 1 ? Colors.green : Colors.blue,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: (progress > 1 ? 1 : progress).toDouble(),
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                progress >= 1 ? Colors.green : Colors.blue,
              ),
            ),
          ),
          
          const SizedBox(height: 12),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Terkumpul',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  Text(
                    'Rp ${nf.format(goal.currentAmount)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    remaining > 0 ? 'Kurang' : 'Target',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  Text(
                    'Rp ${nf.format(remaining > 0 ? remaining : goal.targetAmount)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: remaining > 0 ? Colors.orange : Colors.green,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Helper: Build Category Pie Chart
  Widget _buildCategoryPieChart(
    List<dynamic> topCategories,
    double totalExpense,
    NumberFormat nf,
  ) {
    final colors = [
      Colors.red,
      Colors.orange,
      Colors.blue,
      Colors.green,
      Colors.purple,
      Colors.pink,
    ];
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 50,
                sections: topCategories.take(6).toList().asMap().entries.map((entry) {
                  final idx = entry.key;
                  final cat = entry.value as Map;
                  final amount = (cat['total'] as num?)?.toDouble() ?? 0;
                  final percentage = totalExpense > 0 ? (amount / totalExpense * 100) : 0;
                  
                  return PieChartSectionData(
                    value: amount,
                    title: '${percentage.toStringAsFixed(0)}%',
                    color: colors[idx % colors.length],
                    radius: 50,
                    titleStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Legend
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: topCategories.take(6).toList().asMap().entries.map((entry) {
              final idx = entry.key;
              final cat = entry.value as Map;
              final catName = cat['category'] ?? 'Tidak diketahui';
              final amount = (cat['total'] as num?)?.toDouble() ?? 0;
              
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: colors[idx % colors.length],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$catName (Rp ${nf.format(amount)})',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _PeriodDialogOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  const _PeriodDialogOption({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  if (subtitle != null)
                    Text(subtitle!, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}

class _QuickStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final String? trend;

  const _QuickStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.trend,
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
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              if (trend != null) ...[
                const Spacer(),
                Text(
                  trend!,
                  style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
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
}
