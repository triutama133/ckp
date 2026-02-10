import 'package:catatan_keuangan_pintar/services/auth_service.dart';
import 'package:catatan_keuangan_pintar/services/db_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite/sqflite.dart';
 

class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  static const _prefLastSync = 'sync_last_at';
  static const _prefStrategy = 'sync_conflict_strategy'; // last_write_wins | local_wins | remote_wins

  final SupabaseClient _supabase = Supabase.instance.client;
  Timer? _autoTimer;
  bool _autoRunning = false;

  static const _prefAutoSync = 'sync_auto_enabled';
  static const _prefInterval = 'sync_interval_min';

  Future<String> getStrategy() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefStrategy) ?? 'last_write_wins';
  }

  Future<void> setStrategy(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefStrategy, value);
  }

  Future<int> _lastSyncMs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefLastSync) ?? 0;
  }

  Future<void> _setLastSyncMs(int ms) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefLastSync, ms);
  }

  Future<void> syncAll() async {
    final strategy = await getStrategy();
    final lastSync = await _lastSyncMs();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final userId = AuthService.instance.userId;
    
    // CRITICAL: Ensure user profile exists in public.users BEFORE syncing
    // This prevents FK constraint errors on messages/transactions
    await _ensureUserProfileExists(userId);
    await _backfillLocalUserId(userId);
    
    final groups = await DBService.instance.getGroups();
    final groupIds = groups.map((g) => g.id).toList();

    // IMPORTANT: Sync order matters! Tables MUST be synced in dependency order:
    // 1. Independent tables first (no FK dependencies)
    // 2. Then tables that depend on them
    
    // Phase 1: Groups & Members (no dependencies)
    await _syncTable('groups', lastSync, nowMs, userId, groupIds, strategy);
    await _syncTable('group_members', lastSync, nowMs, userId, groupIds, strategy);
    
    // Phase 2: Master data (categories, gold types)
    await _syncTable('categories', lastSync, nowMs, userId, groupIds, strategy);
    await _syncTable('gold_types', lastSync, nowMs, userId, groupIds, strategy);
    
    // Phase 3: Accounts & Goals (depend on groups via group_id FK)
    await _syncTable('accounts', lastSync, nowMs, userId, groupIds, strategy);
    await _syncTable('goals', lastSync, nowMs, userId, groupIds, strategy);
    
    // Phase 4: Holdings (depend on gold_types)
    await _syncTable('gold_holdings', lastSync, nowMs, userId, groupIds, strategy);
    
    // Phase 5: Transactions (depend on accounts, goals, groups)
    await _syncTable('transactions', lastSync, nowMs, userId, groupIds, strategy);
    await _syncTable('gold_transactions', lastSync, nowMs, userId, groupIds, strategy);
    
    // Phase 6: Messages (depend on groups)
    await _syncTable('messages', lastSync, nowMs, userId, groupIds, strategy);

    await _setLastSyncMs(nowMs);
  }

  /// Ensure user profile exists in public.users table
  /// This is critical for FK constraints on messages, transactions, etc.
  Future<void> _ensureUserProfileExists(String userId) async {
    try {
      final user = AuthService.instance.currentUser;
      if (user == null) return;

      // Check if profile exists
      final existing = await _supabase
          .from('users')
          .select('id')
          .eq('id', userId)
          .maybeSingle();

      if (existing == null) {
        // Profile doesn't exist - create it
        await _supabase.from('users').upsert({
          'id': userId,
          'email': user.email,
          'full_name': user.userMetadata?['full_name'],
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'id');
        print('✅ User profile created in public.users: $userId');
      }
    } catch (e) {
      print('⚠️ Warning: Could not ensure user profile exists: $e');
      // Don't throw - allow sync to continue
      // User will be created by auth service later
    }
  }

  void startAutoSync({Duration interval = const Duration(minutes: 5)}) {
    if (_autoRunning) {
      stopAutoSync();
    }
    _autoRunning = true;
    _autoTimer = Timer.periodic(interval, (_) async {
      try {
        await syncAll();
      } catch (_) {
        // ignore background errors
      }
    });
  }

  void stopAutoSync() {
    _autoTimer?.cancel();
    _autoTimer = null;
    _autoRunning = false;
  }

  Future<void> startAutoSyncFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_prefAutoSync) ?? true;
    final minutes = prefs.getInt(_prefInterval) ?? 5;
    if (enabled) {
      startAutoSync(interval: Duration(minutes: minutes));
    } else {
      stopAutoSync();
    }
  }

  Future<void> _syncTable(
    String table,
    int lastSyncMs,
    int nowMs,
    String userId,
    List<String> groupIds,
    String strategy,
  ) async {
    final db = await DBService.instance.database;

    // 1) Upload local changes
    final localRows = await db.query(
      table,
      where: 'updatedAt IS NULL OR updatedAt >= ?',
      whereArgs: [lastSyncMs],
    );
    if (localRows.isNotEmpty) {
      final payload = localRows.map((row) => _toRemote(table, row, userId)).toList();
      await _supabase.from(table).upsert(payload);
    }

    // 2) Download remote changes
    final iso = DateTime.fromMillisecondsSinceEpoch(lastSyncMs).toIso8601String();
    PostgrestFilterBuilder<dynamic> query = _supabase.from(table).select().gte('updated_at', iso);

    final groupFilter = groupIds.map((g) => '"$g"').join(',');

    if (table == 'groups') {
      if (groupIds.isNotEmpty) {
        query = query.or('created_by.eq.$userId,id.in.($groupFilter)');
      } else {
        query = query.eq('created_by', userId);
      }
    } else if (table == 'group_members') {
      if (groupIds.isNotEmpty) {
        query = query.or('user_id.eq.$userId,group_id.in.($groupFilter)');
      } else {
        query = query.eq('user_id', userId);
      }
    } else if (_hasUserId(table)) {
      if (groupIds.isNotEmpty && _hasGroupId(table)) {
        query = query.or('user_id.eq.$userId,group_id.in.($groupFilter)');
      } else {
        query = query.eq('user_id', userId);
      }
    } else if (_hasGroupId(table)) {
      // Tables like accounts, goals, transactions: have group_id but no user_id
      // Pull data belonging to user's groups + personal (group_id IS NULL handled by RLS)
      if (groupIds.isNotEmpty) {
        query = query.or('group_id.is.null,group_id.in.($groupFilter)');
      }
      // If no groups, Supabase RLS should filter by auth user
    }
    // For categories: no user_id, no group_id — pull everything (RLS filters by user)

    final remoteRows = await query;
    if (remoteRows is! List) return;

    for (final r in remoteRows) {
      final remote = Map<String, dynamic>.from(r as Map);
      final local = _fromRemote(table, remote);
      final id = local['id'];
      if (id == null) continue;

      final localExisting = await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
      if (localExisting.isEmpty) {
        await db.insert(table, local, conflictAlgorithm: ConflictAlgorithm.replace);
        continue;
      }

      if (strategy == 'remote_wins') {
        await db.update(table, local, where: 'id = ?', whereArgs: [id]);
        continue;
      }

      if (strategy == 'local_wins') {
        // keep local
        continue;
      }

      // last_write_wins
      final localUpdated = (localExisting.first['updatedAt'] as int?) ?? 0;
      final remoteUpdated = local['updatedAt'] as int? ?? 0;
      if (remoteUpdated >= localUpdated) {
        await db.update(table, local, where: 'id = ?', whereArgs: [id]);
      }
    }
  }

  bool _hasUserId(String table) {
    // Only tables that have user_id in the Supabase schema
    return [
      'messages',
      'gold_types',
      'gold_holdings',
      'gold_transactions',
      'accounts',
      'categories',
      'goals',
      'transactions',
    ].contains(table);
  }

  bool _hasGroupId(String table) {
    return [
      'accounts',
      'goals',
      'transactions',
      'messages',
      'group_members',
      'groups',
      'gold_holdings',
      'gold_transactions',
    ].contains(table);
  }

  Map<String, dynamic> _toRemote(String table, Map<String, Object?> local, String userId) {
    final out = <String, dynamic>{};
    
    // Columns to exclude per table (exist locally but not in Supabase)
    final excludeColumns = <String, Set<String>>{
      'groups': {'version'},
      'group_members': {'version'},
      'group_invites': {'version'},
    };
    final exclude = excludeColumns[table] ?? {};
    
    local.forEach((key, value) {
      if (exclude.contains(key)) return;
      
      final remoteKey = _toSnakeKey(key);
      if (_isDateField(key)) {
        if (value == null) {
          out[remoteKey] = null;
        } else {
          final ms = value is int ? value : int.tryParse(value.toString()) ?? 0;
          out[remoteKey] = DateTime.fromMillisecondsSinceEpoch(ms).toIso8601String();
        }
      } else if (key == 'isIncome' || key == 'isSystem' || key == 'isActive') {
        out[remoteKey] = value == 1 || value == true;
      } else {
        out[remoteKey] = value;
      }
    });
    if (table == 'groups') {
      final createdBy = out['created_by']?.toString();
      if (createdBy == null || createdBy.isEmpty || createdBy == 'local_user' || createdBy == 'auto') {
        out['created_by'] = userId;
      }
    }
    if (_hasUserId(table)) {
      out['user_id'] = out['user_id'] ?? userId;
    }
    return out;
  }

  Map<String, Object?> _fromRemote(String table, Map<String, dynamic> remote) {
    final out = <String, Object?>{};
    
    // Columns to exclude per table (exist in Supabase but not locally)
    final excludeRemoteColumns = <String, Set<String>>{
      // No exclusions needed now that Account model has groupId
    };
    final exclude = excludeRemoteColumns[table] ?? {};
    
    remote.forEach((key, value) {
      if (exclude.contains(key)) return;
      
      final localKey = _toCamelKey(key);
      if (_isDateField(localKey)) {
        if (value == null) {
          out[localKey] = null;
        } else {
          final dt = DateTime.parse(value.toString());
          out[localKey] = dt.millisecondsSinceEpoch;
        }
      } else if (localKey == 'isIncome' || localKey == 'isSystem' || localKey == 'isActive') {
        out[localKey] = (value == true) ? 1 : 0;
      } else {
        out[localKey] = value;
      }
    });
    return out;
  }

  bool _isDateField(String key) {
    return key == 'createdAt' || key == 'updatedAt' || key == 'deletedAt'
        || key == 'completedAt' || key == 'joinedAt' || key == 'usedAt'
        || key == 'expiresAt' || key == 'targetDate' || key == 'date';
  }

  Future<void> _backfillLocalUserId(String userId) async {
    final db = await DBService.instance.database;
    final tables = ['accounts', 'categories', 'goals', 'transactions'];
    for (final table in tables) {
      try {
        await db.rawUpdate(
          "UPDATE $table SET userId = ? WHERE userId IS NULL OR userId = ''",
          [userId],
        );
      } catch (_) {
        // Ignore if table/column doesn't exist yet on older local schemas
      }
    }

    // Backfill group ownership and membership
    try {
      await db.rawUpdate(
        "UPDATE groups SET createdBy = ? WHERE createdBy IS NULL OR createdBy = '' OR createdBy = 'local_user' OR createdBy = 'auto'",
        [userId],
      );
    } catch (_) {}

    try {
      await db.rawUpdate(
        "UPDATE group_members SET userId = ? WHERE userId IS NULL OR userId = ''",
        [userId],
      );
    } catch (_) {}
  }

  String _toSnakeKey(String key) {
    const mapping = {
      'createdAt': 'created_at',
      'updatedAt': 'updated_at',
      'deletedAt': 'deleted_at',
      'isIncome': 'is_income',
      'isSystem': 'is_system',
      'isActive': 'is_active',
      'messageId': 'message_id',
      'accountId': 'account_id',
      'goalId': 'goal_id',
      'groupId': 'group_id',
      'userId': 'user_id',
      'targetAmount': 'target_amount',
      'currentAmount': 'current_amount',
      'targetDate': 'target_date',
      'completedAt': 'completed_at',
      'createdBy': 'created_by',
      'joinedAt': 'joined_at',
      'usedAt': 'used_at',
      'expiresAt': 'expires_at',
      'typeId': 'type_id',
      'pricePerGram': 'price_per_gram',
      'txType': 'tx_type',
      'totalValue': 'total_value',
      'purchasePrice': 'purchase_price',
      'imageUrl': 'image_url',
      'voiceUrl': 'voice_url',
    };
    return mapping[key] ?? key;
  }

  String _toCamelKey(String key) {
    const mapping = {
      'created_at': 'createdAt',
      'updated_at': 'updatedAt',
      'deleted_at': 'deletedAt',
      'is_income': 'isIncome',
      'is_system': 'isSystem',
      'is_active': 'isActive',
      'message_id': 'messageId',
      'account_id': 'accountId',
      'goal_id': 'goalId',
      'group_id': 'groupId',
      'user_id': 'userId',
      'target_amount': 'targetAmount',
      'current_amount': 'currentAmount',
      'target_date': 'targetDate',
      'completed_at': 'completedAt',
      'created_by': 'createdBy',
      'joined_at': 'joinedAt',
      'used_at': 'usedAt',
      'expires_at': 'expiresAt',
      'type_id': 'typeId',
      'price_per_gram': 'pricePerGram',
      'tx_type': 'txType',
      'total_value': 'totalValue',
      'purchase_price': 'purchasePrice',
      'image_url': 'imageUrl',
      'voice_url': 'voiceUrl',
    };
    return mapping[key] ?? key;
  }
}
