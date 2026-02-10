import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:catatan_keuangan_pintar/services/db_service.dart';
import 'package:catatan_keuangan_pintar/services/auth_service.dart';

/// Professional auto-sync service for offline-first architecture
/// Local-first: all data saved locally first, then synced to cloud when network available
class AutoSyncService {
  AutoSyncService._();
  static final AutoSyncService instance = AutoSyncService._();

  final _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _syncTimer;
  
  bool _isOnline = false;
  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  
  final _pendingSync = <String, List<Map<String, dynamic>>>{};
  
  bool get isOnline => _isOnline;
  bool get isSyncing => _isSyncing;
  DateTime? get lastSyncTime => _lastSyncTime;

  /// Initialize auto-sync service
  Future<void> initialize() async {
    // Check initial connectivity
    final result = await _connectivity.checkConnectivity();
    _isOnline = !result.contains(ConnectivityResult.none);

    // Listen to connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((results) {
      final wasOnline = _isOnline;
      _isOnline = !results.contains(ConnectivityResult.none);
      
      // If we just came online, trigger sync
      if (!wasOnline && _isOnline) {
        _triggerSync();
      }
    });

    // Periodic sync every 5 minutes when online
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_isOnline && !_isSyncing) {
        _triggerSync();
      }
    });
  }

  /// Sync a single message to Supabase
  Future<void> syncMessage(Message message) async {
    if (!_isOnline) {
      // Queue for later sync
      _pendingSync.putIfAbsent('messages', () => []).add({
        'id': message.id,
        'group_id': message.groupId,
        'user_id': AuthService.instance.userId,
        'text': message.text,
        'is_system': message.isSystem,
        'created_at': message.createdAt.toIso8601String(),
        'updated_at': message.createdAt.toIso8601String(),
      });
      return;
    }

    try {
      await Supabase.instance.client.from('messages').upsert({
        'id': message.id,
        'group_id': message.groupId,
        'user_id': AuthService.instance.userId,
        'text': message.text,
        'is_system': message.isSystem,
        'created_at': message.createdAt.toIso8601String(),
        'updated_at': message.createdAt.toIso8601String(),
      });
    } catch (e) {
      // Store in pending queue if sync fails
      _pendingSync.putIfAbsent('messages', () => []).add({
        'id': message.id,
        'group_id': message.groupId,
        'user_id': AuthService.instance.userId,
        'text': message.text,
        'is_system': message.isSystem,
        'created_at': message.createdAt.toIso8601String(),
        'updated_at': message.createdAt.toIso8601String(),
      });
    }
  }

  /// Sync a single transaction to Supabase
  Future<void> syncTransaction(TransactionModel transaction) async {
    if (!_isOnline) {
      // Queue for later sync
      _pendingSync.putIfAbsent('transactions', () => []).add({
        'id': transaction.id,
        'message_id': transaction.messageId,
        'amount': transaction.amount,
        'currency': transaction.currency,
        'category': transaction.category,
        'description': transaction.description,
        'date': transaction.date.toIso8601String(),
        'created_at': transaction.createdAt.toIso8601String(),
        'is_income': transaction.isIncome,
        'type': transaction.type,
        'scope': transaction.scope,
        'group_id': transaction.groupId,
        'account_id': transaction.accountId,
        'goal_id': transaction.goalId,
        'user_id': AuthService.instance.userId,
      });
      return;
    }

    try {
      await Supabase.instance.client.from('transactions').upsert({
        'id': transaction.id,
        'message_id': transaction.messageId,
        'amount': transaction.amount,
        'currency': transaction.currency,
        'category': transaction.category,
        'description': transaction.description,
        'date': transaction.date.toIso8601String(),
        'created_at': transaction.createdAt.toIso8601String(),
        'is_income': transaction.isIncome,
        'type': transaction.type,
        'scope': transaction.scope,
        'group_id': transaction.groupId,
        'account_id': transaction.accountId,
        'goal_id': transaction.goalId,
        'user_id': AuthService.instance.userId,
      });
    } catch (e) {
      // Store in pending queue if sync fails
      _pendingSync.putIfAbsent('transactions', () => []).add({
        'id': transaction.id,
        'message_id': transaction.messageId,
        'amount': transaction.amount,
        'currency': transaction.currency,
        'category': transaction.category,
        'description': transaction.description,
        'date': transaction.date.toIso8601String(),
        'created_at': transaction.createdAt.toIso8601String(),
        'is_income': transaction.isIncome,
        'type': transaction.type,
        'scope': transaction.scope,
        'group_id': transaction.groupId,
        'account_id': transaction.accountId,
        'goal_id': transaction.goalId,
        'user_id': AuthService.instance.userId,
      });
    }
  }

  /// Trigger full sync of pending items
  Future<void> _triggerSync() async {
    if (_isSyncing || !_isOnline || _pendingSync.isEmpty) return;

    _isSyncing = true;
    try {
      // Sync all pending messages
      final pendingMessages = _pendingSync['messages'] ?? [];
      if (pendingMessages.isNotEmpty) {
        try {
          await Supabase.instance.client.from('messages').upsert(pendingMessages);
          _pendingSync['messages'] = [];
        } catch (_) {
          // Keep in queue for retry
        }
      }

      // Sync all pending transactions
      final pendingTransactions = _pendingSync['transactions'] ?? [];
      if (pendingTransactions.isNotEmpty) {
        try {
          await Supabase.instance.client.from('transactions').upsert(pendingTransactions);
          _pendingSync['transactions'] = [];
        } catch (_) {
          // Keep in queue for retry
        }
      }

      _lastSyncTime = DateTime.now();
    } finally {
      _isSyncing = false;
    }
  }

  /// Manually trigger sync
  Future<void> syncNow() async {
    await _triggerSync();
  }

  /// Get pending sync count for UI display
  int get pendingSyncCount {
    return _pendingSync.values.fold(0, (sum, list) => sum + list.length);
  }

  /// Dispose resources
  void dispose() {
    _connectivitySubscription?.cancel();
    _syncTimer?.cancel();
  }
}
