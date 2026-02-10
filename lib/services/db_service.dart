import 'dart:async';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:catatan_keuangan_pintar/services/builtin_categories.dart';
import 'package:catatan_keuangan_pintar/services/auth_service.dart';

// Models
class Message {
  final String id;
  final String text;
  final DateTime createdAt;
  final TransactionModel? parsedTransaction;
  final bool isSystem;
  final String? groupId;

  Message({required this.id, required this.text, required this.createdAt, this.parsedTransaction, this.isSystem = false, this.groupId});

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'text': text,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'isSystem': isSystem ? 1 : 0,
      'groupId': groupId,
    };
  }

  static Message fromMap(Map<String, Object?> map, {TransactionModel? tx}) {
    return Message(
      id: map['id'] as String,
      text: map['text'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
      parsedTransaction: tx,
      isSystem: (map['isSystem'] as int?) == 1,
      groupId: map['groupId'] as String?,
    );
  }
}

class TransactionModel {
  final String id;
  final String? messageId;
  final double amount;
  final String currency;
  final String? category;
  final String? description;
  final DateTime date;
  final DateTime createdAt;
  final bool isIncome;
  final String? type; // 'income' | 'expense' | 'saving' | 'investment'
  final String? accountId; // linked account ID
  final String? goalId; // linked goal ID (untuk saving/investment)
  final String? imageUrl; // foto struk hasil OCR
  final String? voiceUrl; // voice note URL
  final String scope; // 'personal' | 'shared'
  final String? groupId; // optional group id for shared transactions

  TransactionModel({
    required this.id,
    this.messageId,
    required this.amount,
    required this.currency,
    this.category,
    this.description,
    required this.date,
    required this.createdAt,
    this.isIncome = false,
    this.type,
    this.scope = 'personal',
    this.groupId,
    this.accountId,
    this.goalId,
    this.imageUrl,
    this.voiceUrl,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'messageId': messageId,
      'amount': amount,
      'currency': currency,
      'category': category,
      'description': description,
      'date': date.millisecondsSinceEpoch,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'isIncome': isIncome ? 1 : 0,
      'type': type,
      'accountId': accountId,
      'goalId': goalId,
      'imageUrl': imageUrl,
      'voiceUrl': voiceUrl,
      'scope': scope,
      'groupId': groupId,
    };
  }

  static TransactionModel fromMap(Map<String, Object?> map) {
    return TransactionModel(
      id: map['id'] as String,
      messageId: map['messageId'] as String?,
      amount: (map['amount'] as num).toDouble(),
      currency: map['currency'] as String,
      category: map['category'] as String?,
      description: map['description'] as String?,
      date: DateTime.fromMillisecondsSinceEpoch(map['date'] as int),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
      isIncome: (map['isIncome'] as int?) == 1,
      type: map['type'] as String?,
      accountId: map['accountId'] as String?,
      goalId: map['goalId'] as String?,
      imageUrl: map['imageUrl'] as String?,
      voiceUrl: map['voiceUrl'] as String?,
      scope: (map['scope'] as String?) ?? 'personal',
      groupId: (map['groupId'] as String?) ,
    );
  }
}

// Category model for user-manageable categories
class Category {
  final String id;
  final String name;
  final String type; // 'income'|'expense'|'saving'|'investment'
  final String keywords; // comma-separated keywords
  final DateTime createdAt;

  Category({required this.id, required this.name, required this.type, this.keywords = '', required this.createdAt});

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'keywords': keywords,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  static Category fromMap(Map<String, Object?> m) {
    return Category(
      id: m['id'] as String,
      name: m['name'] as String,
      type: m['type'] as String,
      keywords: (m['keywords'] as String?) ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int),
    );
  }
}

// Account model untuk sumber dana (Bank, Cash, E-Wallet, dll)
class Account {
  final String id;
  final String name;
  final String type; // 'bank'|'cash'|'ewallet'|'credit_card'
  final String? icon; // nama icon atau emoji
  final double balance;
  final String? color; // hex color
  final DateTime createdAt;
  final DateTime? deletedAt;
  final String scope; // 'personal'|'shared'
  final String? groupId; // for group accounts

  Account({
    required this.id,
    required this.name,
    required this.type,
    this.icon,
    this.balance = 0.0,
    this.color,
    required this.createdAt,
    this.deletedAt,
    this.scope = 'personal',
    this.groupId,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'icon': icon,
      'balance': balance,
      'color': color,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'deletedAt': deletedAt?.millisecondsSinceEpoch,
      'scope': scope,
      'groupId': groupId,
    };
  }

  static Account fromMap(Map<String, Object?> m) {
    return Account(
      id: m['id'] as String,
      name: m['name'] as String,
      type: m['type'] as String,
      icon: m['icon'] as String?,
      balance: (m['balance'] as num?)?.toDouble() ?? 0.0,
      color: m['color'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int),
      deletedAt: m['deletedAt'] != null ? DateTime.fromMillisecondsSinceEpoch(m['deletedAt'] as int) : null,
      scope: (m['scope'] as String?) ?? 'personal',
      groupId: m['groupId'] as String?,
    );
  }

  Account copyWith({double? balance}) {
    return Account(
      id: id,
      name: name,
      type: type,
      icon: icon,
      balance: balance ?? this.balance,
      color: color,
      createdAt: createdAt,
      deletedAt: deletedAt,
      scope: scope,
      groupId: groupId,
    );
  }
}

// Goal/Target model untuk target tabungan
class Goal {
  final String id;
  final String name;
  final String? description;
  final double targetAmount;
  final double currentAmount;
  final DateTime? targetDate;
  final String? icon;
  final String? color;
  final DateTime createdAt;
  final DateTime? completedAt;
  final bool isActive;
  final String scope; // 'personal' | 'group'
  final String? groupId; // when scope is group

  Goal({
    required this.id,
    required this.name,
    this.description,
    required this.targetAmount,
    this.currentAmount = 0.0,
    this.targetDate,
    this.icon,
    this.color,
    required this.createdAt,
    this.completedAt,
    this.isActive = true,
    this.scope = 'personal',
    this.groupId,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'targetAmount': targetAmount,
      'currentAmount': currentAmount,
      'targetDate': targetDate?.millisecondsSinceEpoch,
      'icon': icon,
      'color': color,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'completedAt': completedAt?.millisecondsSinceEpoch,
      'isActive': isActive ? 1 : 0,
      'scope': scope,
      'groupId': groupId,
    };
  }

  static Goal fromMap(Map<String, Object?> m) {
    return Goal(
      id: m['id'] as String,
      name: m['name'] as String,
      description: m['description'] as String?,
      targetAmount: (m['targetAmount'] as num).toDouble(),
      currentAmount: (m['currentAmount'] as num?)?.toDouble() ?? 0.0,
      targetDate: m['targetDate'] != null ? DateTime.fromMillisecondsSinceEpoch(m['targetDate'] as int) : null,
      icon: m['icon'] as String?,
      color: m['color'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int),
      completedAt: m['completedAt'] != null ? DateTime.fromMillisecondsSinceEpoch(m['completedAt'] as int) : null,
      isActive: (m['isActive'] as int?) == 1,
      scope: (m['scope'] as String?) ?? 'personal',
      groupId: m['groupId'] as String?,
    );
  }

  double get progressPercentage => targetAmount > 0 ? (currentAmount / targetAmount * 100).clamp(0, 100) : 0;
  
  Goal copyWith({double? currentAmount, DateTime? completedAt, bool? isActive, String? scope, String? groupId}) {
    return Goal(
      id: id,
      name: name,
      description: description,
      targetAmount: targetAmount,
      currentAmount: currentAmount ?? this.currentAmount,
      targetDate: targetDate,
      icon: icon,
      color: color,
      createdAt: createdAt,
      completedAt: completedAt ?? this.completedAt,
      isActive: isActive ?? this.isActive,
      scope: scope ?? this.scope,
      groupId: groupId ?? this.groupId,
    );
  }
}

// Group untuk kolaborasi keluarga/tim
class Group {
  final String id;
  final String name;
  final String? description;
  final String? icon;
  final DateTime createdAt;
  final String createdBy;

  Group({
    required this.id,
    required this.name,
    this.description,
    this.icon,
    required this.createdAt,
    required this.createdBy,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'icon': icon,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'createdBy': createdBy,
    };
  }

  static Group fromMap(Map<String, Object?> m) {
    return Group(
      id: m['id'] as String,
      name: m['name'] as String,
      description: m['description'] as String?,
      icon: m['icon'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int),
      createdBy: m['createdBy'] as String,
    );
  }
}

// Group member model: tracks membership, role, and status
class GroupMember {
  final String id;
  final String groupId;
  final String userId;
  final String? email;
  final String role; // 'owner'|'admin'|'member'
  final String status; // 'invited'|'accepted'|'left'
  final DateTime? joinedAt;

  GroupMember({required this.id, required this.groupId, required this.userId, this.email, this.role = 'member', this.status = 'invited', this.joinedAt});

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'groupId': groupId,
      'userId': userId,
      'email': email,
      'role': role,
      'status': status,
      'joinedAt': joinedAt?.millisecondsSinceEpoch,
    };
  }

  static GroupMember fromMap(Map<String, Object?> m) {
    return GroupMember(
      id: m['id'] as String,
      groupId: m['groupId'] as String,
      userId: m['userId'] as String,
      email: m['email'] as String?,
      role: (m['role'] as String?) ?? 'member',
      status: (m['status'] as String?) ?? 'invited',
      joinedAt: m['joinedAt'] != null ? DateTime.fromMillisecondsSinceEpoch(m['joinedAt'] as int) : null,
    );
  }
}

// Invite token model for group invitations
class GroupInvite {
  final String id;
  final String groupId;
  final String token;
  final String createdBy;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime? usedAt;

  GroupInvite({required this.id, required this.groupId, required this.token, required this.createdBy, required this.createdAt, this.expiresAt, this.usedAt});

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'groupId': groupId,
      'token': token,
      'createdBy': createdBy,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'expiresAt': expiresAt?.millisecondsSinceEpoch,
      'usedAt': usedAt?.millisecondsSinceEpoch,
    };
  }

  static GroupInvite fromMap(Map<String, Object?> m) {
    return GroupInvite(
      id: m['id'] as String,
      groupId: m['groupId'] as String,
      token: m['token'] as String,
      createdBy: m['createdBy'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int),
      expiresAt: m['expiresAt'] != null ? DateTime.fromMillisecondsSinceEpoch(m['expiresAt'] as int) : null,
      usedAt: m['usedAt'] != null ? DateTime.fromMillisecondsSinceEpoch(m['usedAt'] as int) : null,
    );
  }
}

// Gold savings models
class GoldType {
  final String id;
  final String name;
  final double pricePerGram;
  final String currency;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? userId;
  final String scope; // 'personal'|'group'
  final String? groupId;
  final DateTime? deletedAt;

  GoldType({
    required this.id,
    required this.name,
    required this.pricePerGram,
    this.currency = 'IDR',
    required this.createdAt,
    this.updatedAt,
    this.userId,
    this.scope = 'personal',
    this.groupId,
    this.deletedAt,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'pricePerGram': pricePerGram,
      'currency': currency,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt?.millisecondsSinceEpoch,
      'userId': userId,
      'scope': scope,
      'groupId': groupId,
      'deletedAt': deletedAt?.millisecondsSinceEpoch,
    };
  }

  static GoldType fromMap(Map<String, Object?> m) {
    return GoldType(
      id: m['id'] as String,
      name: m['name'] as String,
      pricePerGram: (m['pricePerGram'] as num?)?.toDouble() ?? 0.0,
      currency: (m['currency'] as String?) ?? 'IDR',
      createdAt: DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int),
      updatedAt: m['updatedAt'] != null ? DateTime.fromMillisecondsSinceEpoch(m['updatedAt'] as int) : null,
      userId: m['userId'] as String?,
      scope: (m['scope'] as String?) ?? 'personal',
      groupId: m['groupId'] as String?,
      deletedAt: m['deletedAt'] != null ? DateTime.fromMillisecondsSinceEpoch(m['deletedAt'] as int) : null,
    );
  }
}

class GoldHolding {
  final String id;
  final String typeId;
  final double grams;
  final double? purchasePrice; // Average purchase price per gram
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? userId;
  final String scope; // 'personal'|'group'
  final String? groupId;
  final DateTime? deletedAt;

  GoldHolding({
    required this.id,
    required this.typeId,
    required this.grams,
    this.purchasePrice,
    required this.createdAt,
    this.updatedAt,
    this.userId,
    this.scope = 'personal',
    this.groupId,
    this.deletedAt,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'typeId': typeId,
      'grams': grams,
      'purchasePrice': purchasePrice,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt?.millisecondsSinceEpoch,
      'userId': userId,
      'scope': scope,
      'groupId': groupId,
      'deletedAt': deletedAt?.millisecondsSinceEpoch,
    };
  }

  static GoldHolding fromMap(Map<String, Object?> m) {
    return GoldHolding(
      id: m['id'] as String,
      typeId: m['typeId'] as String,
      grams: (m['grams'] as num?)?.toDouble() ?? 0.0,
      purchasePrice: (m['purchasePrice'] as num?)?.toDouble(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int),
      updatedAt: m['updatedAt'] != null ? DateTime.fromMillisecondsSinceEpoch(m['updatedAt'] as int) : null,
      userId: m['userId'] as String?,
      scope: (m['scope'] as String?) ?? 'personal',
      groupId: m['groupId'] as String?,
      deletedAt: m['deletedAt'] != null ? DateTime.fromMillisecondsSinceEpoch(m['deletedAt'] as int) : null,
    );
  }
}

class GoldTransaction {
  final String id;
  final String typeId;
  final String txType; // buy/sell/installment
  final String mode; // physical/digital/installment
  final double grams;
  final double pricePerGram;
  final double totalValue;
  final DateTime date;
  final String? note;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? userId;
  final String scope; // 'personal'|'group'
  final String? groupId;
  final DateTime? deletedAt;

  GoldTransaction({
    required this.id,
    required this.typeId,
    required this.txType,
    required this.mode,
    required this.grams,
    required this.pricePerGram,
    required this.totalValue,
    required this.date,
    this.note,
    required this.createdAt,
    this.updatedAt,
    this.userId,
    this.scope = 'personal',
    this.groupId,
    this.deletedAt,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'typeId': typeId,
      'txType': txType,
      'mode': mode,
      'grams': grams,
      'pricePerGram': pricePerGram,
      'totalValue': totalValue,
      'date': date.millisecondsSinceEpoch,
      'note': note,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt?.millisecondsSinceEpoch,
      'userId': userId,
      'scope': scope,
      'groupId': groupId,
      'deletedAt': deletedAt?.millisecondsSinceEpoch,
    };
  }

  static GoldTransaction fromMap(Map<String, Object?> m) {
    return GoldTransaction(
      id: m['id'] as String,
      typeId: m['typeId'] as String,
      txType: (m['txType'] as String?) ?? 'buy',
      mode: (m['mode'] as String?) ?? 'physical',
      grams: (m['grams'] as num?)?.toDouble() ?? 0.0,
      pricePerGram: (m['pricePerGram'] as num?)?.toDouble() ?? 0.0,
      totalValue: (m['totalValue'] as num?)?.toDouble() ?? 0.0,
      date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
      note: m['note'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int),
      updatedAt: m['updatedAt'] != null ? DateTime.fromMillisecondsSinceEpoch(m['updatedAt'] as int) : null,
      userId: m['userId'] as String?,
      scope: (m['scope'] as String?) ?? 'personal',
      groupId: m['groupId'] as String?,
      deletedAt: m['deletedAt'] != null ? DateTime.fromMillisecondsSinceEpoch(m['deletedAt'] as int) : null,
    );
  }
}

class DBService {
  DBService._privateConstructor();
  static final DBService instance = DBService._privateConstructor();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB('catatan_keuangan.db');
    return _db!;
  }

  Future<Database> _initDB(String fileName) async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, fileName);

    return openDatabase(
      path,
      version: 18,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            text TEXT,
            createdAt INTEGER,
            updatedAt INTEGER,
            version INTEGER DEFAULT 1,
            userId TEXT,
            isSystem INTEGER DEFAULT 0,
            groupId TEXT,
            deletedAt INTEGER
          )
        ''');

        await db.execute('''
          CREATE TABLE transactions (
            id TEXT PRIMARY KEY,
            messageId TEXT,
            amount REAL,
            currency TEXT,
            category TEXT,
            description TEXT,
            date INTEGER,
            createdAt INTEGER,
            updatedAt INTEGER,
            version INTEGER DEFAULT 1,
            userId TEXT,
            isIncome INTEGER,
            type TEXT,
            accountId TEXT,
            goalId TEXT,
            imageUrl TEXT,
            voiceUrl TEXT,
            deletedAt INTEGER,
            scope TEXT DEFAULT 'personal',
            groupId TEXT
          )
        ''');
        
        // categories table for user-managed categories
        await db.execute('''
          CREATE TABLE IF NOT EXISTS categories (
            id TEXT PRIMARY KEY,
            name TEXT,
            type TEXT,
            keywords TEXT,
            createdAt INTEGER,
            updatedAt INTEGER,
            version INTEGER DEFAULT 1,
            userId TEXT,
            deletedAt INTEGER
          )
        ''');

        // accounts table untuk sumber dana
        await db.execute('''
          CREATE TABLE accounts (
            id TEXT PRIMARY KEY,
            name TEXT,
            type TEXT,
            icon TEXT,
            balance REAL DEFAULT 0,
            color TEXT,
            createdAt INTEGER,
            updatedAt INTEGER,
            version INTEGER DEFAULT 1,
            userId TEXT,
            deletedAt INTEGER,
            scope TEXT DEFAULT 'personal',
            groupId TEXT
          )
        ''');

        // goals table untuk target tabungan
        await db.execute('''
          CREATE TABLE goals (
            id TEXT PRIMARY KEY,
            name TEXT,
            description TEXT,
            targetAmount REAL,
            currentAmount REAL DEFAULT 0,
            targetDate INTEGER,
            icon TEXT,
            color TEXT,
            createdAt INTEGER,
            updatedAt INTEGER,
            version INTEGER DEFAULT 1,
            userId TEXT,
            completedAt INTEGER,
            isActive INTEGER DEFAULT 1,
            scope TEXT DEFAULT 'personal',
            groupId TEXT,
            deletedAt INTEGER
          )
        ''');

        // groups table untuk kolaborasi
        await db.execute('''
          CREATE TABLE groups (
            id TEXT PRIMARY KEY,
            name TEXT,
            description TEXT,
            icon TEXT,
            createdAt INTEGER,
            updatedAt INTEGER,
            version INTEGER DEFAULT 1,
            createdBy TEXT,
            deletedAt INTEGER
          )
        ''');

        // group_members table: membership, role and status
        await db.execute('''
          CREATE TABLE group_members (
            id TEXT PRIMARY KEY,
            groupId TEXT,
            userId TEXT,
            role TEXT DEFAULT 'member',
            status TEXT DEFAULT 'invited',
            joinedAt INTEGER,
            createdAt INTEGER,
            updatedAt INTEGER,
            version INTEGER DEFAULT 1,
            deletedAt INTEGER
          )
        ''');

        // group_invites table: token-based invites for sharing
        await db.execute('''
          CREATE TABLE group_invites (
            id TEXT PRIMARY KEY,
            groupId TEXT,
            token TEXT,
            createdBy TEXT,
            createdAt INTEGER,
            expiresAt INTEGER,
            usedAt INTEGER,
            updatedAt INTEGER,
            version INTEGER DEFAULT 1
          )
        ''');

        // gold types (brand) table
        await db.execute('''
          CREATE TABLE gold_types (
            id TEXT PRIMARY KEY,
            name TEXT,
            pricePerGram REAL,
            currency TEXT,
            createdAt INTEGER,
            updatedAt INTEGER,
            version INTEGER DEFAULT 1,
            userId TEXT,
            deletedAt INTEGER
          )
        ''');

        // gold holdings summary per type
        await db.execute('''
          CREATE TABLE gold_holdings (
            id TEXT PRIMARY KEY,
            typeId TEXT,
            grams REAL DEFAULT 0,
            purchasePrice REAL,
            createdAt INTEGER,
            updatedAt INTEGER,
            version INTEGER DEFAULT 1,
            userId TEXT,
            scope TEXT DEFAULT 'personal',
            groupId TEXT,
            deletedAt INTEGER
          )
        ''');

        // gold transactions history
        await db.execute('''
          CREATE TABLE gold_transactions (
            id TEXT PRIMARY KEY,
            typeId TEXT,
            txType TEXT, -- buy/sell/installment
            mode TEXT, -- physical/digital/installment
            grams REAL,
            pricePerGram REAL,
            totalValue REAL,
            date INTEGER,
            note TEXT,
            createdAt INTEGER,
            updatedAt INTEGER,
            version INTEGER DEFAULT 1,
            userId TEXT,
            scope TEXT DEFAULT 'personal',
            groupId TEXT,
            deletedAt INTEGER
          )
        ''');

        // seed default account (Cash)
        await db.insert('accounts', {
          'id': 'default_cash',
          'name': 'Kas',
          'type': 'cash',
          'icon': '💵',
          'balance': 0,
          'color': '#4CAF50',
          'createdAt': DateTime.now().millisecondsSinceEpoch,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
          'version': 1,
          'userId': 'local_user',
          'scope': 'personal',
        });

        // seed builtin categories from BUILTIN_CATEGORIES into categories table
        for (final entry in BUILTIN_CATEGORIES) {
          final name = entry['category'] as String;
          final type = entry['type'] as String;
          final kws = (entry['keywords'] as List).cast<String>().join(',');
          final id = 'builtin_' + name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
          await db.insert('categories', {
            'id': id,
            'name': name,
            'type': type,
            'keywords': kws,
            'createdAt': DateTime.now().millisecondsSinceEpoch,
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
            'version': 1,
            'userId': 'local_user',
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
       },
  onUpgrade: (db, oldVersion, newVersion) async {
         if (oldVersion < 2) {
           // add isIncome column with default 0
           await db.execute('ALTER TABLE transactions ADD COLUMN isIncome INTEGER DEFAULT 0');
         }
         if (oldVersion < 3) {
           // add isSystem to messages
           await db.execute('ALTER TABLE messages ADD COLUMN isSystem INTEGER DEFAULT 0');
         }
         if (oldVersion < 4) {
           // add type to transactions
           await db.execute('ALTER TABLE transactions ADD COLUMN type TEXT');
         }
         if (oldVersion < 5) {
           // Backfill: mark old transactions as 'saving' when description/category suggests tabungan/tabung/simpan/setor/tarik
           await db.execute("UPDATE transactions SET type = 'saving' WHERE (type IS NULL OR type = '') AND (LOWER(COALESCE(description,'')) LIKE '%tabung%' OR LOWER(COALESCE(description,'')) LIKE '%tabungan%' OR LOWER(COALESCE(description,'')) LIKE '%simpan%' OR LOWER(COALESCE(description,'')) LIKE '%setor%' OR LOWER(COALESCE(description,'')) LIKE '%tarik%' OR LOWER(COALESCE(category,'')) LIKE '%tabung%' OR LOWER(COALESCE(category,'')) LIKE '%tabungan%')");
         }
         if (oldVersion < 6) {
           // add deletedAt for soft-delete
           await db.execute('ALTER TABLE transactions ADD COLUMN deletedAt INTEGER');
         }
        if (oldVersion < 7) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS categories (
              id TEXT PRIMARY KEY,
              name TEXT,
              type TEXT,
              keywords TEXT,
              createdAt INTEGER
            )
          ''');
            // seed builtin categories during upgrade as well
            for (final entry in BUILTIN_CATEGORIES) {
              final name = entry['category'] as String;
              final type = entry['type'] as String;
              final kws = (entry['keywords'] as List).cast<String>().join(',');
              final id = 'builtin_' + name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
              await db.insert('categories', {
                'id': id,
                'name': name,
                'type': type,
                'keywords': kws,
                'createdAt': DateTime.now().millisecondsSinceEpoch,
              }, conflictAlgorithm: ConflictAlgorithm.ignore);
            }
        }
        if (oldVersion < 8) {
          // Add new columns to transactions
          try { await db.execute('ALTER TABLE transactions ADD COLUMN accountId TEXT'); } catch (_) {}
          try { await db.execute('ALTER TABLE transactions ADD COLUMN goalId TEXT'); } catch (_) {}
          try { await db.execute('ALTER TABLE transactions ADD COLUMN imageUrl TEXT'); } catch (_) {}
          try { await db.execute('ALTER TABLE transactions ADD COLUMN voiceUrl TEXT'); } catch (_) {}
          
          // Add groupId to messages
          try { await db.execute('ALTER TABLE messages ADD COLUMN groupId TEXT'); } catch (_) {}
          
          // Create new tables
          await db.execute('''
            CREATE TABLE IF NOT EXISTS accounts (
              id TEXT PRIMARY KEY,
              name TEXT,
              type TEXT,
              icon TEXT,
              balance REAL DEFAULT 0,
              color TEXT,
              createdAt INTEGER,
              deletedAt INTEGER
            )
          ''');

          await db.execute('''
            CREATE TABLE IF NOT EXISTS goals (
              id TEXT PRIMARY KEY,
              name TEXT,
              description TEXT,
              targetAmount REAL,
              currentAmount REAL DEFAULT 0,
              targetDate INTEGER,
              icon TEXT,
              color TEXT,
              createdAt INTEGER,
              completedAt INTEGER,
              isActive INTEGER DEFAULT 1,
              scope TEXT DEFAULT 'personal',
              groupId TEXT
            )
          ''');

          await db.execute('''
            CREATE TABLE IF NOT EXISTS groups (
              id TEXT PRIMARY KEY,
              name TEXT,
              description TEXT,
              icon TEXT,
              createdAt INTEGER,
              createdBy TEXT
            )
          ''');

          // Seed default cash account
          await db.insert('accounts', {
            'id': 'default_cash',
            'name': 'Kas',
            'type': 'cash',
            'icon': '💵',
            'balance': 0,
            'color': '#4CAF50',
            'createdAt': DateTime.now().millisecondsSinceEpoch,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        if (oldVersion < 9) {
          // Add scope column to accounts and transactions to distinguish personal/shared
          try {
            await db.execute("ALTER TABLE accounts ADD COLUMN scope TEXT DEFAULT 'personal'");
          } catch (_) {}
          try {
            await db.execute("ALTER TABLE transactions ADD COLUMN scope TEXT DEFAULT 'personal'");
          } catch (_) {}
        }
        if (oldVersion < 10) {
          try {
            await db.execute("ALTER TABLE transactions ADD COLUMN groupId TEXT");
          } catch (_) {}
        }
        if (oldVersion < 11) {
          // membership and invite tables
          await db.execute('''
            CREATE TABLE IF NOT EXISTS group_members (
              id TEXT PRIMARY KEY,
              groupId TEXT,
              userId TEXT,
              role TEXT DEFAULT 'member',
              status TEXT DEFAULT 'invited',
              joinedAt INTEGER
            )
          ''');

          await db.execute('''
            CREATE TABLE IF NOT EXISTS group_invites (
              id TEXT PRIMARY KEY,
              groupId TEXT,
              token TEXT,
              createdBy TEXT,
              createdAt INTEGER,
              expiresAt INTEGER,
              usedAt INTEGER
            )
          ''');
        }
        if (oldVersion < 12) {
          // Add scope + groupId to goals
          try {
            await db.execute("ALTER TABLE goals ADD COLUMN scope TEXT DEFAULT 'personal'");
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE goals ADD COLUMN groupId TEXT');
          } catch (_) {}
        }
        if (oldVersion < 13) {
          // Add sync columns for offline-first sync
          final cols = [
            "ALTER TABLE messages ADD COLUMN updatedAt INTEGER",
            "ALTER TABLE messages ADD COLUMN version INTEGER DEFAULT 1",
            "ALTER TABLE messages ADD COLUMN userId TEXT",
            "ALTER TABLE messages ADD COLUMN deletedAt INTEGER",
            "ALTER TABLE transactions ADD COLUMN updatedAt INTEGER",
            "ALTER TABLE transactions ADD COLUMN version INTEGER DEFAULT 1",
            "ALTER TABLE transactions ADD COLUMN userId TEXT",
            "ALTER TABLE categories ADD COLUMN updatedAt INTEGER",
            "ALTER TABLE categories ADD COLUMN version INTEGER DEFAULT 1",
            "ALTER TABLE categories ADD COLUMN userId TEXT",
            "ALTER TABLE categories ADD COLUMN deletedAt INTEGER",
            "ALTER TABLE accounts ADD COLUMN updatedAt INTEGER",
            "ALTER TABLE accounts ADD COLUMN version INTEGER DEFAULT 1",
            "ALTER TABLE accounts ADD COLUMN userId TEXT",
            "ALTER TABLE goals ADD COLUMN updatedAt INTEGER",
            "ALTER TABLE goals ADD COLUMN version INTEGER DEFAULT 1",
            "ALTER TABLE goals ADD COLUMN userId TEXT",
            "ALTER TABLE goals ADD COLUMN deletedAt INTEGER",
            "ALTER TABLE groups ADD COLUMN updatedAt INTEGER",
            "ALTER TABLE groups ADD COLUMN version INTEGER DEFAULT 1",
            "ALTER TABLE groups ADD COLUMN deletedAt INTEGER",
            "ALTER TABLE group_members ADD COLUMN updatedAt INTEGER",
            "ALTER TABLE group_members ADD COLUMN version INTEGER DEFAULT 1",
            "ALTER TABLE group_members ADD COLUMN deletedAt INTEGER",
            "ALTER TABLE group_invites ADD COLUMN updatedAt INTEGER",
            "ALTER TABLE group_invites ADD COLUMN version INTEGER DEFAULT 1"
          ];
          for (final sql in cols) {
            try { await db.execute(sql); } catch (_) {}
          }

          final now = DateTime.now().millisecondsSinceEpoch;
          try { await db.execute('UPDATE messages SET updatedAt = COALESCE(updatedAt, createdAt, ?)', [now]); } catch (_) {}
          try { await db.execute('UPDATE transactions SET updatedAt = COALESCE(updatedAt, createdAt, ?)', [now]); } catch (_) {}
          try { await db.execute('UPDATE categories SET updatedAt = COALESCE(updatedAt, createdAt, ?)', [now]); } catch (_) {}
          try { await db.execute('UPDATE accounts SET updatedAt = COALESCE(updatedAt, createdAt, ?)', [now]); } catch (_) {}
          try { await db.execute('UPDATE goals SET updatedAt = COALESCE(updatedAt, createdAt, ?)', [now]); } catch (_) {}
          try { await db.execute('UPDATE groups SET updatedAt = COALESCE(updatedAt, createdAt, ?)', [now]); } catch (_) {}
          try { await db.execute('UPDATE group_members SET updatedAt = COALESCE(updatedAt, joinedAt, ?)', [now]); } catch (_) {}
          try { await db.execute('UPDATE group_invites SET updatedAt = COALESCE(updatedAt, createdAt, ?)', [now]); } catch (_) {}
        }
        if (oldVersion < 14) {
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS gold_types (
                id TEXT PRIMARY KEY,
                name TEXT,
                pricePerGram REAL,
                currency TEXT,
                createdAt INTEGER,
                updatedAt INTEGER,
                version INTEGER DEFAULT 1,
                userId TEXT,
                deletedAt INTEGER
              )
            ''');
          } catch (_) {}
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS gold_holdings (
                id TEXT PRIMARY KEY,
                typeId TEXT,
                grams REAL DEFAULT 0,
                purchasePrice REAL,
                createdAt INTEGER,
                updatedAt INTEGER,
                version INTEGER DEFAULT 1,
                userId TEXT,
                scope TEXT DEFAULT 'personal',
                groupId TEXT,
                deletedAt INTEGER
              )
            ''');
          } catch (_) {}
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS gold_transactions (
                id TEXT PRIMARY KEY,
                typeId TEXT,
                txType TEXT,
                mode TEXT,
                grams REAL,
                pricePerGram REAL,
                totalValue REAL,
                date INTEGER,
                note TEXT,
                createdAt INTEGER,
                updatedAt INTEGER,
                version INTEGER DEFAULT 1,
                userId TEXT,
                scope TEXT DEFAULT 'personal',
                groupId TEXT,
                deletedAt INTEGER
              )
            ''');
          } catch (_) {}
        }
        if (oldVersion < 15) {
          // Add purchasePrice column to gold_holdings
          try {
            await db.execute("ALTER TABLE gold_holdings ADD COLUMN purchasePrice REAL");
          } catch (_) {}
        }
        if (oldVersion < 16) {
          // Add groupId column to accounts for group wallet support
          try {
            await db.execute("ALTER TABLE accounts ADD COLUMN groupId TEXT");
          } catch (_) {}
        }
        if (oldVersion < 17) {
          // Add createdAt column to group_members for sync compatibility
          try {
            await db.execute("ALTER TABLE group_members ADD COLUMN createdAt INTEGER");
          } catch (_) {}
        }
        if (oldVersion < 18) {
          try { await db.execute("ALTER TABLE gold_holdings ADD COLUMN scope TEXT DEFAULT 'personal'"); } catch (_) {}
          try { await db.execute("ALTER TABLE gold_holdings ADD COLUMN groupId TEXT"); } catch (_) {}
          try { await db.execute("ALTER TABLE gold_transactions ADD COLUMN scope TEXT DEFAULT 'personal'"); } catch (_) {}
          try { await db.execute("ALTER TABLE gold_transactions ADD COLUMN groupId TEXT"); } catch (_) {}
        }
       },
        onOpen: (db) async {
          // ensure builtin categories exist (idempotent)
          try {
            for (final entry in BUILTIN_CATEGORIES) {
              final name = entry['category'] as String;
              final type = entry['type'] as String;
              final kws = (entry['keywords'] as List).cast<String>().join(',');
              final id = 'builtin_' + name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
              await db.insert('categories', {
                'id': id,
                'name': name,
                'type': type,
                'keywords': kws,
                'createdAt': DateTime.now().millisecondsSinceEpoch,
              }, conflictAlgorithm: ConflictAlgorithm.ignore);
            }
          } catch (_) {
            // ignore - safe best-effort
          }
        },
     );
   }

  Future<void> insertMessage(Message message) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final map = message.toMap();
    map['updatedAt'] = now;
    map['version'] = (map['version'] as int?) ?? 1;
    map['userId'] = map['userId'] ?? AuthService.instance.userId;
    await db.insert('messages', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteMessage(String messageId) async {
    final db = await database;
    // Delete associated transactions first
    await db.delete('transactions', where: 'messageId = ?', whereArgs: [messageId]);
    // Delete the message
    await db.delete('messages', where: 'id = ?', whereArgs: [messageId]);
  }

  Future<void> deleteTransaction(String transactionId) async {
    final db = await database;
    final ts = DateTime.now().millisecondsSinceEpoch;
    await db.rawUpdate(
      'UPDATE transactions SET deletedAt = ?, updatedAt = ?, version = COALESCE(version, 0) + 1 WHERE id = ?',
      [ts, ts, transactionId],
    );
  }

  Future<void> insertTransaction(TransactionModel tx) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final map = tx.toMap();
    map['updatedAt'] = now;
    map['version'] = (map['version'] as int?) ?? 1;
    map['userId'] = map['userId'] ?? AuthService.instance.userId;
    await db.insert('transactions', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteTransactionsSoft(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final idsPlaceholders = ids.map((_) => '?').join(',');
    await db.rawUpdate('UPDATE transactions SET deletedAt = ?, updatedAt = ?, version = COALESCE(version, 0) + 1 WHERE id IN ($idsPlaceholders)', [ts, ts, ...ids]);
  }

  // Helper to ensure queries exclude soft-deleted rows
  String _notDeletedWhere(String baseWhere) {
    if (baseWhere.trim().isEmpty) return 'deletedAt IS NULL';
    return '($baseWhere) AND deletedAt IS NULL';
  }

  Future<List<TransactionModel>> getTransactionsBetween(DateTime start, DateTime end) async {
    final db = await database;
    final where = _notDeletedWhere('date >= ? AND date <= ?');
    final maps = await db.query('transactions', where: where, whereArgs: [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch], orderBy: 'date DESC');
    return maps.map((m) => TransactionModel.fromMap(m)).toList();
  }

  Future<List<TransactionModel>> getRecentTransactions(int limit) async {
    final db = await database;
    final maps = await db.query('transactions', where: 'deletedAt IS NULL', orderBy: 'date DESC', limit: limit);
    return maps.map((m) => TransactionModel.fromMap(m)).toList();
  }

  Future<Map<String, dynamic>> getTotalsBetween(DateTime start, DateTime end, {String? groupId, String? scope}) async {
    final db = await database;
    final startMs = start.millisecondsSinceEpoch;
    final endMs = end.millisecondsSinceEpoch;

    // build optional group/scope filter
    String extraSql = '';
    final extraArgs = <Object?>[];
    if (groupId != null) {
      if (groupId == 'all') {
        // no-op
      } else {
        extraSql += ' AND groupId = ?';
        extraArgs.add(groupId);
      }
    } else {
      extraSql += ' AND groupId IS NULL';
    }
    if (scope != null) {
      extraSql += ' AND scope = ?';
      extraArgs.add(scope);
    }

    // total income (isIncome = 1)
    final incomeRow = await db.rawQuery(
      'SELECT IFNULL(SUM(amount),0) as total FROM transactions WHERE isIncome = 1 AND date BETWEEN ? AND ? AND deletedAt IS NULL $extraSql',
      [startMs, endMs, ...extraArgs],
    );
    final totalIncome = (incomeRow.first['total'] as num).toDouble();

    // total expense (isIncome = 0) but exclude asset-withdrawal rows (type LIKE '%_out') because those are transfers back to cash
    final expenseRow = await db.rawQuery(
      "SELECT IFNULL(SUM(amount),0) as total FROM transactions WHERE isIncome = 0 AND (type IS NULL OR type NOT LIKE '%_out') AND date BETWEEN ? AND ? AND deletedAt IS NULL $extraSql",
      [startMs, endMs, ...extraArgs],
    );
    final totalExpense = (expenseRow.first['total'] as num).toDouble();

    // saving: compute deposits minus withdrawals (saving_out)
    final savingRow = await db.rawQuery('''
      SELECT
        IFNULL(SUM(CASE WHEN type = 'saving' THEN amount ELSE 0 END),0) as saved,
        IFNULL(SUM(CASE WHEN type = 'saving_out' THEN amount ELSE 0 END),0) as saved_out
      FROM transactions
      WHERE date BETWEEN ? AND ? AND deletedAt IS NULL $extraSql
    ''', [startMs, endMs, ...extraArgs]);
    final saved = (savingRow.first['saved'] as num).toDouble();
    final savedOut = (savingRow.first['saved_out'] as num).toDouble();
    final netSaving = saved - savedOut;

    // investment: compute deposits minus withdrawals (investment_out)
    final investRow = await db.rawQuery('''
      SELECT
        IFNULL(SUM(CASE WHEN type = 'investment' THEN amount ELSE 0 END),0) as invested,
        IFNULL(SUM(CASE WHEN type = 'investment_out' THEN amount ELSE 0 END),0) as invested_out
      FROM transactions
      WHERE date BETWEEN ? AND ? AND deletedAt IS NULL $extraSql
    ''', [startMs, endMs, ...extraArgs]);
    final invested = (investRow.first['invested'] as num).toDouble();
    final investedOut = (investRow.first['invested_out'] as num).toDouble();
    final netInvestment = invested - investedOut;

    // total transaction count (exclude soft-deleted)
    final countRow = await db.rawQuery('SELECT COUNT(1) as c FROM transactions WHERE date BETWEEN ? AND ? AND deletedAt IS NULL $extraSql', [startMs, endMs, ...extraArgs]);
    final count = (countRow.first['c'] as int) ?? 0;

    // balance = income - expense (transfers to saving/investment already excluded from expense above)
    final balance = totalIncome - totalExpense;

    return {
      'income': totalIncome,
      'expense': totalExpense,
      'saving': netSaving,
      'investment': netInvestment,
      'count': count,
      'balance': balance,
    };
  }

  // New: get savings summary grouped by category or total
  Future<List<Map<String, Object?>>> getSavingsSummaryByPeriod({
    required DateTime start,
    required DateTime end,
    required String period, // 'day' | 'month' | 'year' | 'all'
    int limit = 100,
  }) async {
    final db = await database;
    final startMs = start.millisecondsSinceEpoch;
    final endMs = end.millisecondsSinceEpoch;

    if (period == 'all') {
      final rows = await db.rawQuery('''
        SELECT
          IFNULL(SUM(CASE WHEN type = 'saving' THEN amount WHEN type = 'saving_out' THEN -amount ELSE 0 END),0) as net,
          IFNULL(SUM(CASE WHEN type = 'saving' THEN amount ELSE 0 END),0) as deposits,
          IFNULL(SUM(CASE WHEN type = 'saving_out' THEN amount ELSE 0 END),0) as withdrawals,
          IFNULL(MAX(COALESCE(date, createdAt)), 0) as lastAt
        FROM transactions
      ''' );

      final r = rows.first;
      return [
        {
          'category': 'Semua',
          'net': (r['net'] as num).toDouble(),
          'deposits': (r['deposits'] as num).toDouble(),
          'withdrawals': (r['withdrawals'] as num).toDouble(),
          'count': 0,
          'lastAt': (r['lastAt'] as int?) ?? 0,
        }
      ];
    }

    final rows = await db.rawQuery('''
      SELECT
        COALESCE(category, '-') as category,
        SUM(CASE WHEN type = 'saving' THEN amount ELSE 0 END) as deposits,
        SUM(CASE WHEN type = 'saving_out' THEN amount ELSE 0 END) as withdrawals,
        SUM(CASE WHEN type = 'saving' THEN amount WHEN type = 'saving_out' THEN -amount ELSE 0 END) as net,
        COUNT(1) as cnt,
        IFNULL(MAX(COALESCE(date, createdAt)), 0) as lastAt
      FROM transactions
      WHERE COALESCE(date, createdAt) BETWEEN ? AND ? AND deletedAt IS NULL
        AND (type = 'saving' OR type = 'saving_out' OR LOWER(COALESCE(category, '')) LIKE '%tabung%')
      GROUP BY category
      ORDER BY net DESC
      LIMIT ?
    ''', [startMs, endMs, limit]);

    // Normalize numeric types to Dart-friendly types
    return rows.map((r) {
      return {
        'category': r['category'] as String,
        'net': (r['net'] as num?)?.toDouble() ?? 0.0,
        'deposits': (r['deposits'] as num?)?.toDouble() ?? 0.0,
        'withdrawals': (r['withdrawals'] as num?)?.toDouble() ?? 0.0,
        'count': (r['cnt'] as int?) ?? 0,
        'lastAt': (r['lastAt'] as int?) ?? 0,
      };
    }).toList();
  }

  Future<List<Message>> getMessages() async {
    final db = await database;
    final maps = await db.query('messages', orderBy: 'createdAt DESC');
    final List<Message> items = [];
    for (final map in maps) {
      // try find transaction
      final txMaps = await db.query('transactions', where: 'messageId = ?', whereArgs: [map['id']]);
      TransactionModel? tx;
      if (txMaps.isNotEmpty) {
        tx = TransactionModel.fromMap(txMaps.first);
      }
      items.add(Message.fromMap(map, tx: tx));
    }
    return items;
  }

  Future<List<Message>> getMessagesForGroup(String? groupId) async {
    final db = await database;
    String? where;
    List<Object?> args = [];
    if (groupId == null) {
      // personal messages (groupId IS NULL)
      where = 'groupId IS NULL';
    } else if (groupId == 'all') {
      where = null;
    } else {
      where = 'groupId = ?';
      args = [groupId];
    }
    final maps = await db.query('messages', where: where, whereArgs: args, orderBy: 'createdAt DESC');
    final List<Message> items = [];
    for (final map in maps) {
      final txMaps = await db.query('transactions', where: 'messageId = ?', whereArgs: [map['id']]);
      TransactionModel? tx;
      if (txMaps.isNotEmpty) tx = TransactionModel.fromMap(txMaps.first);
      items.add(Message.fromMap(map, tx: tx));
    }
    return items;
  }

  // Category CRUD
  Future<List<Category>> getCategories() async {
    final db = await database;
    final maps = await db.query('categories', orderBy: 'name ASC');
    return maps.map((m) => Category.fromMap(m)).toList();
  }

  Future<void> insertCategory(Category c) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final map = c.toMap();
    map['updatedAt'] = now;
    map['version'] = (map['version'] as int?) ?? 1;
    map['userId'] = map['userId'] ?? AuthService.instance.userId;
    await db.insert('categories', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateCategory(Category c) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final map = c.toMap();
    map['updatedAt'] = now;
    map['version'] = (map['version'] as int?) ?? 1;
    map['userId'] = map['userId'] ?? AuthService.instance.userId;
    await db.update('categories', map, where: 'id = ?', whereArgs: [c.id]);
  }

  Future<void> deleteCategory(String id) async {
    final db = await database;
    await db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }

  // Heuristic: extract top tokens from transaction descriptions for a given category name.
  // Returns top `limit` tokens (lowercased), excluding short tokens and stopwords.
  Future<List<String>> topTokensForCategory(String? category, {int limit = 6}) async {
    final db = await database;
    final Map<String, int> counts = {};

    // small stopword list (id + english)
    final stopwords = <String>{
      'di','ke','dari','dan','yang','untuk','pada','dengan','ini','itu','saya','kamu','anda','oleh','sebuah','sebagai','the','a','an','ke',
    };

    // collect descriptions where category matches or description contains category keyword
    final lowerCat = (category ?? '').toLowerCase().trim();
    List<Map<String, Object?>> rows = [];
    if (lowerCat.isNotEmpty) {
      rows = await db.rawQuery("SELECT description FROM transactions WHERE LOWER(COALESCE(category,'')) = ? AND deletedAt IS NULL", [lowerCat]);
      if (rows.isEmpty) {
        rows = await db.rawQuery("SELECT description FROM transactions WHERE LOWER(COALESCE(description,'')) LIKE ? AND deletedAt IS NULL", ['%$lowerCat%']);
      }
    } else {
      rows = await db.rawQuery('SELECT description FROM transactions WHERE deletedAt IS NULL');
    }

    for (final r in rows) {
      final desc = (r['description'] as String?) ?? '';
      final text = desc.toLowerCase();
      final matches = RegExp(r"[a-z0-9]+", caseSensitive: false).allMatches(text);
      for (final m in matches) {
        final token = m.group(0)!.trim();
        if (token.length < 3) continue;
        if (stopwords.contains(token)) continue;
        counts[token] = (counts[token] ?? 0) + 1;
      }
    }

    // include builtin keywords for category if present
    for (final entry in BUILTIN_CATEGORIES) {
      final name = (entry['category'] as String);
      if (name.toLowerCase() == lowerCat) {
        final kws = (entry['keywords'] as List).cast<String>();
        for (final k in kws) {
          final tok = k.toLowerCase().trim();
          if (tok.length < 2) continue;
          counts[tok] = (counts[tok] ?? 0) + 3; // boost builtin keywords
        }
      }
    }

    // also include tokens from the category name itself
    if (lowerCat.isNotEmpty) {
      final m = RegExp(r"[a-z0-9]+", caseSensitive: false).allMatches(lowerCat);
      for (final mm in m) {
        final t = mm.group(0)!.trim();
        if (t.length < 2) continue;
        if (stopwords.contains(t)) continue;
        counts[t] = (counts[t] ?? 0) + 2;
      }
    }

    final ordered = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ordered.take(limit).map((e) => e.key).toList();
  }

  // ============ ACCOUNT CRUD ============
  Future<List<Account>> getAccounts({bool includeDeleted = false}) async {
    final db = await database;
    final where = includeDeleted ? null : 'deletedAt IS NULL';
    final maps = await db.query('accounts', where: where, orderBy: 'name ASC');
    return maps.map((m) => Account.fromMap(m)).toList();
  }

  // Get accounts including virtual savings accounts from goals
  Future<List<Account>> getAccountsWithSavings({bool includeDeleted = false, String? groupId}) async {
    final accounts = await getAccounts(includeDeleted: includeDeleted);
    final scopedAccounts = accounts.where((acc) {
      if (groupId == null) {
        return acc.scope == 'personal' || acc.groupId == null;
      }
      if (groupId == 'all') return true;
      return acc.scope == 'group' && acc.groupId == groupId;
    }).toList();

    // Add virtual accounts from savings goals
    final goalScope = groupId == null ? 'personal' : (groupId == 'all' ? null : 'group');
    final goals = await getGoals(activeOnly: true, groupId: groupId, scope: goalScope);
    final savingsAccounts = goals.map((goal) {
      return Account(
        id: 'saving_${goal.id}',
        name: 'Tabungan: ${goal.name}',
        type: 'savings',
        icon: '💰',
        balance: goal.currentAmount,
        color: '#4CAF50',
        createdAt: goal.createdAt,
        scope: goal.groupId == null ? 'personal' : 'group',
      );
    }).toList();

    return [...scopedAccounts, ...savingsAccounts];
  }

  Future<Account?> getAccount(String id) async {
    final db = await database;
    final maps = await db.query('accounts', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Account.fromMap(maps.first);
  }

  Future<void> insertAccount(Account account) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final map = account.toMap();
    map['updatedAt'] = now;
    map['version'] = (map['version'] as int?) ?? 1;
    map['userId'] = map['userId'] ?? AuthService.instance.userId;
    await db.insert('accounts', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateAccount(Account account) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final map = account.toMap();
    map['updatedAt'] = now;
    map['version'] = (map['version'] as int?) ?? 1;
    map['userId'] = map['userId'] ?? AuthService.instance.userId;
    await db.update('accounts', map, where: 'id = ?', whereArgs: [account.id]);
  }

  Future<void> deleteAccount(String id) async {
    final db = await database;
    await db.update('accounts', {'deletedAt': DateTime.now().millisecondsSinceEpoch}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateAccountBalance(String accountId, double newBalance) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.rawUpdate('UPDATE accounts SET balance = ?, updatedAt = ?, version = COALESCE(version, 0) + 1 WHERE id = ?', [newBalance, now, accountId]);
  }

  // ============ GOAL CRUD ============
  Future<List<Goal>> getGoals({bool activeOnly = true, String? groupId, String? scope}) async {
    final db = await database;
    final whereClauses = <String>[];
    final args = <Object?>[];
    if (activeOnly) {
      whereClauses.add('isActive = 1');
    }
    if (groupId != null) {
      if (groupId == 'all') {
        // no group filter
      } else {
        whereClauses.add('groupId = ?');
        args.add(groupId);
      }
    } else {
      whereClauses.add('groupId IS NULL');
    }
    if (scope != null) {
      whereClauses.add('scope = ?');
      args.add(scope);
    }
    final where = whereClauses.isEmpty ? null : whereClauses.join(' AND ');
    final maps = await db.query('goals', where: where, whereArgs: args, orderBy: 'createdAt DESC');
    return maps.map((m) => Goal.fromMap(m)).toList();
  }

  Future<Goal?> getGoal(String id) async {
    final db = await database;
    final maps = await db.query('goals', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Goal.fromMap(maps.first);
  }

  Future<void> insertGoal(Goal goal) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final map = goal.toMap();
    map['updatedAt'] = now;
    map['version'] = (map['version'] as int?) ?? 1;
    map['userId'] = map['userId'] ?? AuthService.instance.userId;
    await db.insert('goals', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateGoal(Goal goal) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final map = goal.toMap();
    map['updatedAt'] = now;
    map['version'] = (map['version'] as int?) ?? 1;
    map['userId'] = map['userId'] ?? AuthService.instance.userId;
    await db.update('goals', map, where: 'id = ?', whereArgs: [goal.id]);
  }

  // ============ GROUP MEMBERSHIP & INVITES ==========
  Future<void> insertGroupMember(GroupMember m) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final map = m.toMap();
    map['updatedAt'] = now;
    map['version'] = (map['version'] as int?) ?? 1;
    await db.insert('group_members', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<GroupMember>> getGroupMembers(String groupId) async {
    final db = await database;
    final maps = await db.query('group_members', where: 'groupId = ? AND deletedAt IS NULL', whereArgs: [groupId], orderBy: "joinedAt DESC");
    return maps.map((m) => GroupMember.fromMap(m)).toList();
  }

  Future<void> updateGroupMemberRole(String memberId, String role) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.rawUpdate('UPDATE group_members SET role = ?, updatedAt = ?, version = COALESCE(version, 0) + 1 WHERE id = ?', [role, now, memberId]);
  }

  Future<void> removeGroupMember(String memberId) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update('group_members', {'deletedAt': now, 'updatedAt': now}, where: 'id = ?', whereArgs: [memberId]);
  }

  Future<void> insertGroupInvite(GroupInvite invite) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final map = invite.toMap();
    map['updatedAt'] = now;
    map['version'] = (map['version'] as int?) ?? 1;
    await db.insert('group_invites', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<GroupInvite?> getInviteByToken(String token) async {
    final db = await database;
    final maps = await db.query('group_invites', where: 'token = ?', whereArgs: [token]);
    if (maps.isEmpty) return null;
    return GroupInvite.fromMap(maps.first);
  }

  Future<void> markInviteUsed(String inviteId) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.rawUpdate('UPDATE group_invites SET usedAt = ?, updatedAt = ?, version = COALESCE(version, 0) + 1 WHERE id = ?', [now, now, inviteId]);
  }

  Future<void> deleteInvite(String inviteId) async {
    final db = await database;
    await db.delete('group_invites', where: 'id = ?', whereArgs: [inviteId]);
  }

  Future<void> deleteGoal(String id) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update('goals', {'isActive': 0, 'deletedAt': now, 'updatedAt': now}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateGoalProgress(String goalId, double amount) async {
    final db = await database;
    final goal = await getGoal(goalId);
    if (goal == null) return;
    
    final newAmount = goal.currentAmount + amount;
    final updates = <String, dynamic>{'currentAmount': newAmount};
    
    // Auto-complete jika mencapai target
    if (newAmount >= goal.targetAmount && goal.completedAt == null) {
      updates['completedAt'] = DateTime.now().millisecondsSinceEpoch;
    }
    
    final now = DateTime.now().millisecondsSinceEpoch;
    updates['updatedAt'] = now;
    await db.update('goals', updates, where: 'id = ?', whereArgs: [goalId]);
    await db.rawUpdate('UPDATE goals SET version = COALESCE(version, 0) + 1 WHERE id = ?', [goalId]);
  }

  // ============ GOLD SAVINGS ============
  Future<List<GoldType>> getGoldTypes() async {
    final db = await database;
    final maps = await db.query('gold_types', where: 'deletedAt IS NULL', orderBy: 'createdAt DESC');
    return maps.map((m) => GoldType.fromMap(m)).toList();
  }

  Future<void> insertGoldType(GoldType type) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final map = type.toMap();
    map['updatedAt'] = now;
    map['version'] = (map['version'] as int?) ?? 1;
    map['userId'] = map['userId'] ?? AuthService.instance.userId;
    await db.insert('gold_types', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateGoldType(GoldType type) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final map = type.toMap();
    map['updatedAt'] = now;
    map['version'] = (map['version'] as int?) ?? 1;
    map['userId'] = map['userId'] ?? AuthService.instance.userId;
    await db.update('gold_types', map, where: 'id = ?', whereArgs: [type.id]);
  }

  Future<void> deleteGoldType(String id) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update('gold_types', {'deletedAt': now, 'updatedAt': now}, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<GoldHolding>> getGoldHoldings({String? groupId}) async {
    final db = await database;
    String where = 'deletedAt IS NULL';
    final args = <Object?>[];
    if (groupId == null) {
      where += ' AND groupId IS NULL';
    } else if (groupId != 'all') {
      where += ' AND groupId = ?';
      args.add(groupId);
    }
    final maps = await db.query('gold_holdings', where: where, whereArgs: args, orderBy: 'createdAt DESC');
    return maps.map((m) => GoldHolding.fromMap(m)).toList();
  }

  Future<List<GoldTransaction>> getGoldTransactions({String? typeId, String? groupId}) async {
    final db = await database;
    final clauses = <String>['deletedAt IS NULL'];
    final args = <Object?>[];
    if (typeId != null) {
      clauses.add('typeId = ?');
      args.add(typeId);
    }
    if (groupId == null) {
      clauses.add('groupId IS NULL');
    } else if (groupId != 'all') {
      clauses.add('groupId = ?');
      args.add(groupId);
    }
    final where = clauses.join(' AND ');
    final maps = await db.query('gold_transactions', where: where, whereArgs: args, orderBy: 'date DESC');
    return maps.map((m) => GoldTransaction.fromMap(m)).toList();
  }

  Future<void> insertGoldTransaction(GoldTransaction tx) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final map = tx.toMap();
    map['updatedAt'] = now;
    map['version'] = (map['version'] as int?) ?? 1;
    map['userId'] = map['userId'] ?? AuthService.instance.userId;
    map['scope'] = map['scope'] ?? (tx.groupId == null ? 'personal' : 'group');
    await db.insert('gold_transactions', map, conflictAlgorithm: ConflictAlgorithm.replace);

    // update holdings
    String where = 'typeId = ? AND deletedAt IS NULL';
    final args = <Object?>[tx.typeId];
    if (tx.groupId == null) {
      where += ' AND groupId IS NULL';
    } else {
      where += ' AND groupId = ?';
      args.add(tx.groupId);
    }
    final existing = await db.query('gold_holdings', where: where, whereArgs: args, limit: 1);
    double newGrams = tx.grams;
    if (existing.isNotEmpty) {
      final current = (existing.first['grams'] as num?)?.toDouble() ?? 0.0;
      newGrams = tx.txType == 'sell' ? (current - tx.grams) : (current + tx.grams);
      final holdingId = existing.first['id'] as String;
      await db.rawUpdate(
        'UPDATE gold_holdings SET grams = ?, updatedAt = ?, version = COALESCE(version,0)+1 WHERE id = ?',
        [newGrams, now, holdingId],
      );
    } else {
      final groupKey = tx.groupId ?? 'personal';
      final holding = GoldHolding(
        id: 'gh_${groupKey}_${tx.typeId}',
        typeId: tx.typeId,
        grams: tx.txType == 'sell' ? -tx.grams : tx.grams,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        userId: AuthService.instance.userId,
        scope: tx.groupId == null ? 'personal' : 'group',
        groupId: tx.groupId,
      );
      await db.insert('gold_holdings', holding.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<Map<String, double>> getGoldSummary({String? groupId}) async {
    final db = await database;
    String where = 'deletedAt IS NULL';
    final args = <Object?>[];
    if (groupId == null) {
      where += ' AND groupId IS NULL';
    } else if (groupId != 'all') {
      where += ' AND groupId = ?';
      args.add(groupId);
    }
    final holdings = await db.query('gold_holdings', where: where, whereArgs: args);
    final types = await db.query('gold_types', where: 'deletedAt IS NULL');
    final priceMap = <String, double>{};
    for (final t in types) {
      priceMap[t['id'] as String] = (t['pricePerGram'] as num?)?.toDouble() ?? 0.0;
    }
    double totalGrams = 0;
    double totalValue = 0;
    for (final h in holdings) {
      final grams = (h['grams'] as num?)?.toDouble() ?? 0.0;
      totalGrams += grams;
      final typeId = h['typeId'] as String;
      final price = priceMap[typeId] ?? 0.0;
      totalValue += grams * price;
    }
    return {'grams': totalGrams, 'value': totalValue};
  }

  // ============ GROUP CRUD ============
  Future<List<Group>> getGroups() async {
    final db = await database;
    final maps = await db.query('groups', where: 'deletedAt IS NULL', orderBy: 'createdAt DESC');
    return maps.map((m) => Group.fromMap(m)).toList();
  }

  Future<Group?> getGroup(String id) async {
    final db = await database;
    final maps = await db.query('groups', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Group.fromMap(maps.first);
  }

  Future<void> insertGroup(Group group) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final map = group.toMap();
    map['updatedAt'] = now;
    map['version'] = (map['version'] as int?) ?? 1;
    final createdBy = map['createdBy'] as String?;
    if (createdBy == null || createdBy.isEmpty || createdBy == 'local_user' || createdBy == 'auto') {
      map['createdBy'] = AuthService.instance.userId;
    }
    await db.insert('groups', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void>updateGroup(Group group) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final map = group.toMap();
    map['updatedAt'] = now;
    map['version'] = (map['version'] as int?) ?? 1;
    await db.update('groups', map, where: 'id = ?', whereArgs: [group.id]);
  }

  Future<void> deleteGroup(String id) async {
    final db = await database;
    // Remove group membership and invites, and detach group from messages/transactions
    await db.transaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await txn.update('group_members', {'deletedAt': now, 'updatedAt': now}, where: 'groupId = ?', whereArgs: [id]);
      await txn.delete('group_invites', where: 'groupId = ?', whereArgs: [id]);
      // detach messages and transactions (keep records but mark groupId NULL)
      await txn.update('messages', {'groupId': null}, where: 'groupId = ?', whereArgs: [id]);
      await txn.update('transactions', {'groupId': null}, where: 'groupId = ?', whereArgs: [id]);
      await txn.update('groups', {'deletedAt': now, 'updatedAt': now}, where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<List<GroupInvite>> getInvitesForGroup(String groupId) async {
    final db = await database;
    final maps = await db.query('group_invites', where: 'groupId = ?', whereArgs: [groupId], orderBy: 'createdAt DESC');
    return maps.map((m) => GroupInvite.fromMap(m)).toList();
  }

  Future<GroupMember?> getMemberByUser(String groupId, String userId) async {
    final db = await database;
    final maps = await db.query('group_members', where: 'groupId = ? AND userId = ?', whereArgs: [groupId, userId]);
    if (maps.isEmpty) return null;
    return GroupMember.fromMap(maps.first);
  }

  Future<void> leaveGroup(String groupId, String userId) async {
    final db = await database;
    final member = await getMemberByUser(groupId, userId);
    if (member == null) return;
    // If owner, prevent leaving; caller should transfer ownership first
    if (member.role == 'owner') {
      throw Exception('owner_cannot_leave_without_transfer');
    }
    await db.delete('group_members', where: 'id = ?', whereArgs: [member.id]);
  }

  Future<void> transferOwnership(String groupId, String newOwnerMemberId) async {
    final db = await database;
    await db.transaction((txn) async {
      // find current owner
      final owners = await txn.query('group_members', where: 'groupId = ? AND role = ?', whereArgs: [groupId, 'owner']);
      if (owners.isNotEmpty) {
        final current = owners.first;
        await txn.update('group_members', {'role': 'admin'}, where: 'id = ?', whereArgs: [current['id']]);
      }
      // promote new owner
      await txn.update('group_members', {'role': 'owner'}, where: 'id = ?', whereArgs: [newOwnerMemberId]);
      // update groups.createdBy to reflect new owner userId
      final newOwner = await txn.query('group_members', where: 'id = ?', whereArgs: [newOwnerMemberId]);
      if (newOwner.isNotEmpty) {
        final uid = newOwner.first['userId'] as String;
        await txn.update('groups', {'createdBy': uid}, where: 'id = ?', whereArgs: [groupId]);
      }
    });
  }

  // ============ STATS & INSIGHTS ============
  Future<Map<String, dynamic>> getDashboardStats({DateTime? start, DateTime? end, String? groupId, String? scope}) async {
    final db = await database;
    final now = DateTime.now();
    final startDate = start ?? DateTime(now.year, now.month, 1);
    final endDate = end ?? DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    
    final totals = await getTotalsBetween(startDate, endDate, groupId: groupId, scope: scope);
    
    // Top categories
    // build optional filters for groupId/scope
    String extraSql = '';
    final extraArgs = <Object?>[];
    if (groupId != null) {
      if (groupId == 'all') {
        // no group filter
      } else {
        extraSql += ' AND groupId = ?';
        extraArgs.add(groupId);
      }
    } else {
      // personal
      extraSql += ' AND groupId IS NULL';
    }
    if (scope != null) {
      extraSql += ' AND scope = ?';
      extraArgs.add(scope);
    }

    final topExpenseQuery = await db.rawQuery('''
      SELECT category, SUM(amount) as total, COUNT(*) as count
      FROM transactions
      WHERE type = 'expense' AND deletedAt IS NULL
        AND date BETWEEN ? AND ?
        AND category IS NOT NULL
        $extraSql
      GROUP BY category
      ORDER BY total DESC
      LIMIT 5
    ''', [startDate.millisecondsSinceEpoch, endDate.millisecondsSinceEpoch, ...extraArgs]);
    
    // Account balances summary - filtered by wallet (group or personal)
    final accountsData = await getAccounts();
    double totalBalance;
    if (groupId != null && groupId != 'all') {
      // Group wallet: only include accounts belonging to this group
      totalBalance = accountsData
          .where((acc) => acc.scope == 'group' && acc.groupId == groupId)
          .fold<double>(0, (sum, acc) => sum + acc.balance);
    } else if (groupId == null) {
      // Personal wallet: only include personal accounts (or group accounts without groupId)
      totalBalance = accountsData
          .where((acc) => acc.scope == 'personal' || acc.groupId == null)
          .fold<double>(0, (sum, acc) => sum + acc.balance);
    } else {
      // All wallets
      totalBalance = accountsData.fold<double>(0, (sum, acc) => sum + acc.balance);
    }
    
    // Active goals progress
    final goalsData = await getGoals(activeOnly: true, groupId: groupId, scope: scope);
    final goalsProgress = goalsData.map((g) => {
      'name': g.name,
      'progress': g.progressPercentage,
      'current': g.currentAmount,
      'target': g.targetAmount,
    }).toList();

    // Gold summary
    final goldSummary = await getGoldSummary(groupId: groupId);
    
    return {
      'income': totals['income'],
      'expense': totals['expense'],
      'saving': totals['saving'],
      'investment': totals['investment'],
      'balance': totals['balance'],
      'transactionCount': totals['count'],
      'topExpenseCategories': topExpenseQuery,
      'totalBalance': totalBalance,
      'accountCount': accountsData.length,
      'goalsProgress': goalsProgress,
      'activeGoalsCount': goalsData.length,
      'goldSummary': goldSummary,
    };
  }

}
