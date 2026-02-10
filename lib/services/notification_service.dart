import 'package:catatan_keuangan_pintar/services/db_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';

class SmartNotificationService {
  SmartNotificationService._();
  static final SmartNotificationService instance = SmartNotificationService._();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(settings);
    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _isInitialized = true;
  }

  /// Generate and show smart insights based on financial data
  Future<List<SmartInsight>> generateInsights() async {
    final insights = <SmartInsight>[];
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    // Get monthly stats
    final monthlyStats = await DBService.instance.getTotalsBetween(startOfMonth, endOfMonth);
    final income = (monthlyStats['income'] as num?)?.toDouble() ?? 0;
    final expense = (monthlyStats['expense'] as num?)?.toDouble() ?? 0;
    final saving = (monthlyStats['saving'] as num?)?.toDouble() ?? 0;

    // Get goals
    final goals = await DBService.instance.getGoals(activeOnly: true, groupId: 'all');

    // Insight 1: Spending vs Income
    if (expense > income * 0.8) {
      insights.add(SmartInsight(
        type: InsightType.warning,
        title: 'Pengeluaran Tinggi!',
        message: 'Pengeluaran bulan ini sudah ${(expense / income * 100).toStringAsFixed(0)}% dari pemasukan. Pertimbangkan untuk mengurangi pengeluaran.',
        priority: InsightPriority.high,
        source: 'Sumber: Data transaksi bulan berjalan',
      ));
    }

    // Insight 2: Positive balance
    if (income > expense && (income - expense) > income * 0.2) {
      insights.add(SmartInsight(
        type: InsightType.positive,
        title: 'Keuangan Sehat!',
        message: 'Saldo bulan ini positif Rp ${NumberFormat('#,##0', 'id').format(income - expense)}. Pertimbangkan untuk menabung lebih.',
        priority: InsightPriority.medium,
        source: 'Sumber: Analisis pendapatan vs pengeluaran',
      ));
    }

    // Insight 3: Goal progress
    for (final goal in goals) {
      final progress = goal.progressPercentage;
      
      if (progress >= 90 && progress < 100) {
        insights.add(SmartInsight(
          type: InsightType.positive,
          title: 'Hampir Tercapai!',
          message: 'Target "${goal.name}" sudah ${progress.toStringAsFixed(0)}%! Kurang Rp ${NumberFormat('#,##0', 'id').format(goal.targetAmount - goal.currentAmount)} lagi.',
          priority: InsightPriority.high,
          goalId: goal.id,
          source: 'Sumber: Progress target finansial',
        ));
      } else if (progress < 20 && goal.targetDate != null) {
        final daysLeft = goal.targetDate!.difference(now).inDays;
        if (daysLeft > 0 && daysLeft < 90) {
          final monthlyNeeded = (goal.targetAmount - goal.currentAmount) / (daysLeft / 30);
          insights.add(SmartInsight(
            type: InsightType.info,
            title: 'Target "${goal.name}"',
            message: 'Untuk mencapai target dalam ${daysLeft} hari, perlu menabung Rp ${NumberFormat('#,##0', 'id').format(monthlyNeeded)} per bulan.',
            priority: InsightPriority.medium,
            goalId: goal.id,
            source: 'Sumber: Target date & sisa target',
          ));
        }
      }
    }

    // Insight 4: Saving habit
    if (saving < income * 0.1 && income > 0) {
      insights.add(SmartInsight(
        type: InsightType.info,
        title: 'Tips Menabung',
        message: 'Cobalah menabung minimal 10% dari pemasukan (Rp ${NumberFormat('#,##0', 'id').format(income * 0.1)}) setiap bulan.',
        priority: InsightPriority.low,
        source: 'Sumber: Aturan tabungan 10% sederhana',
      ));
    }

    // Insight 5: Emergency fund - based on average monthly salary
    final accounts = await DBService.instance.getAccounts();
    final totalBalance = accounts.fold<double>(0, (sum, acc) => sum + acc.balance);
    
    // Calculate average monthly salary from last 3 months
    final threeMonthsAgo = DateTime(now.year, now.month - 3, 1);
    final lastThreeMonthsTx = await DBService.instance.getTransactionsBetween(threeMonthsAgo, now);
    final salaryTotal = lastThreeMonthsTx
        .where((tx) {
          final cat = (tx.category ?? '').toLowerCase();
          return tx.isIncome && (cat.contains('gaji') || cat.contains('tunjangan'));
        })
        .fold<double>(0, (sum, tx) => sum + tx.amount);
    final avgMonthlySalary = salaryTotal / 3;

    final recommendedEmergencyFund = avgMonthlySalary * 6; // 6 months of avg salary

    if (totalBalance < recommendedEmergencyFund && avgMonthlySalary > 0) {
      insights.add(SmartInsight(
        type: InsightType.warning,
        title: 'Dana Darurat',
        message: 'Dana darurat yang direkomendasikan adalah ${NumberFormat('#,##0', 'id').format(recommendedEmergencyFund)} (6x rata-rata gaji per bulan). Saat ini: ${NumberFormat('#,##0', 'id').format(totalBalance)}.',
        priority: InsightPriority.medium,
        source: 'Sumber: Rata-rata gaji 3 bulan terakhir',
      ));
    }

    // Insight 6: Spending trend (compare with last month)
    final lastMonthStart = DateTime(now.year, now.month - 1, 1);
    final lastMonthEnd = DateTime(now.year, now.month, 0, 23, 59, 59);
    final lastMonthStats = await DBService.instance.getTotalsBetween(lastMonthStart, lastMonthEnd);
    final lastMonthExpense = (lastMonthStats['expense'] as num?)?.toDouble() ?? 0;
    
    if (lastMonthExpense > 0 && expense > 0) {
      final changePercent = ((expense - lastMonthExpense) / lastMonthExpense * 100);
      if (changePercent > 20) {
        insights.add(SmartInsight(
          type: InsightType.warning,
          title: 'Pengeluaran Naik Signifikan',
          message: 'Pengeluaran bulan ini naik ${changePercent.toStringAsFixed(0)}% dibanding bulan lalu. Periksa kategori pengeluaran terbesar.',
          priority: InsightPriority.high,
          source: 'Sumber: Perbandingan pengeluaran bulan ini vs bulan lalu',
        ));
      } else if (changePercent < -15) {
        insights.add(SmartInsight(
          type: InsightType.positive,
          title: 'Pengeluaran Menurun!',
          message: 'Hebat! Pengeluaran turun ${changePercent.abs().toStringAsFixed(0)}% dibanding bulan lalu. Pertahankan!',
          priority: InsightPriority.medium,
          source: 'Sumber: Perbandingan pengeluaran bulan ini vs bulan lalu',
        ));
      }
    }

    // Insight 7: Top expense category warning
    final transactions = await DBService.instance.getTransactionsBetween(startOfMonth, endOfMonth);
    final categoryTotals = <String, double>{};
    for (final tx in transactions) {
      if (!tx.isIncome && tx.category != null) {
        categoryTotals[tx.category!] = (categoryTotals[tx.category!] ?? 0) + tx.amount;
      }
    }
    if (categoryTotals.isNotEmpty) {
      final topCategory = categoryTotals.entries.reduce((a, b) => a.value > b.value ? a : b);
      if (topCategory.value > expense * 0.3) {
        insights.add(SmartInsight(
          type: InsightType.info,
          title: 'Kategori Terbesar: ${topCategory.key}',
          message: 'Rp ${NumberFormat('#,##0', 'id').format(topCategory.value)} (${(topCategory.value / expense * 100).toStringAsFixed(0)}% dari total pengeluaran). Cek apakah bisa dihemat.',
          priority: InsightPriority.medium,
          source: 'Sumber: Analisis kategori pengeluaran bulan ini',
        ));
      }
    }

    // Insight 8: Investment suggestion
    if (totalBalance > avgMonthlySalary * 3 && avgMonthlySalary > 0) {
      final investmentSuggestion = totalBalance * 0.2;
      insights.add(SmartInsight(
        type: InsightType.info,
        title: 'Pertimbangkan Investasi',
        message: 'Saldo Anda sudah cukup stabil. Pertimbangkan investasi sekitar Rp ${NumberFormat('#,##0', 'id').format(investmentSuggestion)} untuk pertumbuhan jangka panjang.',
        priority: InsightPriority.low,
        source: 'Sumber: Rekomendasi alokasi aset sederhana',
      ));
    }

    // Insight 9: Saving rate highlight
    if (income > 0) {
      final savingRate = ((income - expense) / income * 100).clamp(-100, 100);
      if (savingRate >= 20) {
        insights.add(SmartInsight(
          type: InsightType.positive,
          title: 'Rasio Menabung Bagus',
          message: 'Rasio menabung bulan ini ${savingRate.toStringAsFixed(0)}%. Terus pertahankan untuk capai tujuan lebih cepat.',
          priority: InsightPriority.medium,
          source: 'Sumber: (Pemasukan - Pengeluaran) / Pemasukan',
        ));
      } else if (savingRate >= 0 && savingRate < 10) {
        insights.add(SmartInsight(
          type: InsightType.info,
          title: 'Rasio Menabung Rendah',
          message: 'Rasio menabung bulan ini ${savingRate.toStringAsFixed(0)}%. Coba sisihkan 10% agar dana darurat cepat terbentuk.',
          priority: InsightPriority.low,
          source: 'Sumber: (Pemasukan - Pengeluaran) / Pemasukan',
        ));
      }
    }

    // Insight 10: Transaction frequency
    if (monthlyStats['count'] != null) {
      final count = (monthlyStats['count'] as num?)?.toInt() ?? 0;
      if (count > 0) {
        final avgPerDay = (count / (endOfMonth.day)).toStringAsFixed(1);
        insights.add(SmartInsight(
          type: InsightType.info,
          title: 'Kebiasaan Transaksi',
          message: 'Rata-rata ${avgPerDay} transaksi per hari. Pertahankan pencatatan agar analisis makin akurat.',
          priority: InsightPriority.low,
          source: 'Sumber: Jumlah transaksi bulan berjalan',
        ));
      }
    }

    // Sort by priority
    insights.sort((a, b) => b.priority.index.compareTo(a.priority.index));

    return insights;
  }

  /// Show notification
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_isInitialized) await initialize();

    const androidDetails = AndroidNotificationDetails(
      'smart_insights',
      'Smart Insights',
      channelDescription: 'Notifikasi pintar tentang keuangan Anda',
      importance: Importance.high,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(id, title, body, details, payload: payload);
  }

  /// Show daily insight notification
  Future<void> showDailyInsight() async {
    final insights = await generateInsights();
    if (insights.isEmpty) return;

    final topInsight = insights.first;
    await showNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: topInsight.title,
      body: topInsight.message,
    );
  }

  /// Schedule daily insights
  Future<void> scheduleDailyInsights() async {
    if (!_isInitialized) await initialize();

    // Fallback daily reminder (content not dynamic in background)
    const androidDetails = AndroidNotificationDetails(
      'daily_reminder',
      'Daily Reminder',
      channelDescription: 'Pengingat harian untuk cek catatan keuangan',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _notifications.periodicallyShow(
      1001,
      'Saatnya cek keuangan',
      'Buka aplikasi untuk melihat insight terbaru.',
      RepeatInterval.daily,
      details,
      androidAllowWhileIdle: true,
    );
  }

  Future<void> cancelDailyInsights() async {
    if (!_isInitialized) await initialize();
    await _notifications.cancel(1001);
  }

  /// Get spending pattern analysis
  Future<SpendingPattern> analyzeSpendingPattern() async {
    final now = DateTime.now();
    final last30Days = now.subtract(const Duration(days: 30));
    
    final stats = await DBService.instance.getTotalsBetween(last30Days, now);
    final expense = (stats['expense'] as num?)?.toDouble() ?? 0;
    final income = (stats['income'] as num?)?.toDouble() ?? 0;
    
    final avgDailyExpense = (expense / 30).toDouble();
    final savingRate = income > 0 ? (((income - expense) / income * 100).toDouble()) : 0.0;
    
    String pattern;
    if (expense > income * 0.9) {
      pattern = 'high_spender';
    } else if (savingRate > 30) {
      pattern = 'saver';
    } else if (savingRate > 10) {
      pattern = 'balanced';
    } else {
      pattern = 'moderate_spender';
    }
    
    return SpendingPattern(
      pattern: pattern,
      avgDailyExpense: avgDailyExpense,
      savingRate: savingRate,
      monthlyExpense: expense,
      monthlyIncome: income,
    );
  }
}

enum InsightType {
  positive,
  warning,
  info,
}

enum InsightPriority {
  low,
  medium,
  high,
}

class SmartInsight {
  final InsightType type;
  final String title;
  final String message;
  final InsightPriority priority;
  final String? goalId;
  final String? actionUrl;
  final String? source;

  SmartInsight({
    required this.type,
    required this.title,
    required this.message,
    required this.priority,
    this.goalId,
    this.actionUrl,
    this.source,
  });

  IconData get icon {
    switch (type) {
      case InsightType.positive:
        return Icons.check_circle;
      case InsightType.warning:
        return Icons.warning;
      case InsightType.info:
        return Icons.info;
    }
  }

  Color get color {
    switch (type) {
      case InsightType.positive:
        return Colors.green;
      case InsightType.warning:
        return Colors.orange;
      case InsightType.info:
        return Colors.blue;
    }
  }
}

class SpendingPattern {
  final String pattern;
  final double avgDailyExpense;
  final double savingRate;
  final double monthlyExpense;
  final double monthlyIncome;

  SpendingPattern({
    required this.pattern,
    required this.avgDailyExpense,
    required this.savingRate,
    required this.monthlyExpense,
    required this.monthlyIncome,
  });

  String get analysis {
    switch (pattern) {
      case 'high_spender':
        return 'Anda cenderung menghabiskan sebagian besar pemasukan. Pertimbangkan untuk mengurangi pengeluaran.';
      case 'saver':
        return 'Luar biasa! Anda menabung lebih dari 30% pemasukan. Terus pertahankan!';
      case 'balanced':
        return 'Keuangan Anda cukup seimbang. Tingkatkan tabungan untuk hasil lebih baik.';
      default:
        return 'Mulai biasakan menabung minimal 10% dari pemasukan setiap bulan.';
    }
  }
}
