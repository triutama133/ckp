import 'dart:async';
import 'package:catatan_keuangan_pintar/services/db_service.dart';
import 'package:catatan_keuangan_pintar/services/builtin_categories.dart';
import 'package:uuid/uuid.dart';

class ParsedTransaction {
  final double amount;
  final String? currency;
  final String? category;
  final String? description;
  final DateTime? date;
  final bool isIncome;
  final String type; // 'income', 'expense', 'saving'
  final String scope; // 'personal' | 'shared'

  ParsedTransaction({
    required this.amount,
    this.currency,
    this.category,
    this.description,
    this.date,
    this.isIncome = false,
    this.type = 'expense',
    this.scope = 'personal',
  });
}

class ParserService {
  ParserService._privateConstructor();
  static final ParserService instance = ParserService._privateConstructor();

  // cache for user-defined categories loaded from DB
  List<Category> _customCategoriesCache = [];
  bool _customLoaded = false;

  Future<void> reloadCustomCategories() async {
    try {
      _customCategoriesCache = await DBService.instance.getCategories();
      _customLoaded = true;
    } catch (_) {
      _customCategoriesCache = [];
      _customLoaded = true;
    }
  }

  // Attempt to find or create a group based on text hints.
  Future<String?> _getOrCreateGroupForText(String text) async {
    final lower = text.toLowerCase();
    // simple hint words to form a group name
    final hintWords = ['keluarga', 'teman', 'rumah', 'kantor', 'rt', 'rumah tangga', 'teman kantor', 'keluarga besar', 'tetangga'];
    String? hint;
    for (final w in hintWords) {
      if (lower.contains(w)) {
        hint = w;
        break;
      }
    }

    final baseName = hint != null ? 'Bersama ${hint[0].toUpperCase()}${hint.substring(1)}' : 'Grup Bersama';

    // check existing groups for similar name
    final groups = await DBService.instance.getGroups();
    for (final g in groups) {
      if (g.name.toLowerCase() == baseName.toLowerCase() || g.name.toLowerCase().contains(baseName.toLowerCase())) {
        return g.id;
      }
    }

    // create new group
    final id = const Uuid().v4();
    final newGroup = Group(id: id, name: baseName, description: null, icon: null, createdAt: DateTime.now(), createdBy: 'auto');
    await DBService.instance.insertGroup(newGroup);
    return id;
  }

  // use BUILTIN_CATEGORIES from builtin_categories.dart
  final List<Map<String, Object>> _categoryMap = BUILTIN_CATEGORIES;

  // Enhanced merchant/brand detection for better categorization
  final Map<String, String> _merchantCategoryMap = {
    // Food & Beverage
    'mcd': 'Makanan & Minuman',
    'mcdonald': 'Makanan & Minuman',
    'kfc': 'Makanan & Minuman',
    'starbucks': 'Makanan & Minuman',
    'indomaret': 'Belanja',
    'alfamart': 'Belanja',
    'tokopedia': 'Belanja Online',
    'shopee': 'Belanja Online',
    'lazada': 'Belanja Online',
    'blibli': 'Belanja Online',
    'grab': 'Transport',
    'gojek': 'Transport',
    'pertamina': 'Bensin',
    'shell': 'Bensin',
    'pln': 'Utilitas',
    'listrik': 'Utilitas',
    'pdam': 'Utilitas',
    'air': 'Utilitas',
    'telkom': 'Internet & Pulsa',
    'indihome': 'Internet & Pulsa',
    'xl': 'Internet & Pulsa',
    'telkomsel': 'Internet & Pulsa',
    'by.u': 'Internet & Pulsa',
    'netflix': 'Hiburan',
    'spotify': 'Hiburan',
    'disney': 'Hiburan',
    'cinema': 'Hiburan',
    'cgv': 'Hiburan',
    'xxi': 'Hiburan',
    'apotik': 'Kesehatan',
    'farmasi': 'Kesehatan',
    'kimia farma': 'Kesehatan',
    'guardian': 'Kesehatan',
    'watsons': 'Kesehatan',
    'rumah sakit': 'Kesehatan',
    'rs': 'Kesehatan',
    'klinik': 'Kesehatan',
  };

  // Enhanced amount parsing supporting Indonesian number format
  double? _parseAmount(String text) {
    final lower = text.toLowerCase();
    
    // Handle Indonesian number words (ribu, juta, miliar)
    final ribuan = RegExp(r'(\d+(?:[,\.]\d+)?)\s*(?:rb|ribu|k)', caseSensitive: false).firstMatch(lower);
    if (ribuan != null) {
      final base = double.tryParse(ribuan.group(1)!.replaceAll(',', '.')) ?? 0;
      return base * 1000;
    }
    
    final jutaan = RegExp(r'(\d+(?:[,\.]\d+)?)\s*(?:jt|juta|m)', caseSensitive: false).firstMatch(lower);
    if (jutaan != null) {
      final base = double.tryParse(jutaan.group(1)!.replaceAll(',', '.')) ?? 0;
      return base * 1000000;
    }
    
    final miliaran = RegExp(r'(\d+(?:[,\.]\d+)?)\s*(?:miliar|milyar|b)', caseSensitive: false).firstMatch(lower);
    if (miliaran != null) {
      final base = double.tryParse(miliaran.group(1)!.replaceAll(',', '.')) ?? 0;
      return base * 1000000000;
    }
    
    // Standard number extraction
    final cleaned = text.replaceAll(RegExp(r"[^0-9,\.]"), ' ').replaceAll(',', '.');
    final match = RegExp(r"(\d+[\d\.]*)").firstMatch(cleaned);
    if (match != null) {
      final amountStr = match.group(1)!.replaceAll('.', '');
      return double.tryParse(amountStr);
    }
    
    return null;
  }

  Future<ParsedTransaction?> parseText(String text) async {
    // Enhanced rule-based parsing with merchant detection and Indonesian number format
    try {
      final lower = text.toLowerCase();

      // detect income keywords
      final incomeKeywords = ['dapat', 'terima', 'bonus', 'gaji', 'masuk', 'menerima', 'terima uang', 'gajian', 'honorarium', 'upah', 'penghasilan', 'komisi', 'dividen'];
      final expenseKeywords = ['beli', 'bayar', 'makan', 'bensin', 'beli', 'roti', 'sembako', 'pakai', 'keluar', 'belanja', 'bayar', 'transfer', 'kirim', 'top up', 'isi ulang'];
      final savingKeywords = ['tabungan', 'dana darurat', 'savings', 'tabung', 'simpan', 'setor', 'menabung'];

      bool likelyIncome = incomeKeywords.any((k) => lower.contains(k));
      bool likelyExpense = expenseKeywords.any((k) => lower.contains(k));
      bool likelySaving = savingKeywords.any((k) => lower.contains(k));

      // Use enhanced amount parser
      final amount = _parseAmount(text);
      if (amount != null && amount > 0) {
        // Check merchant/brand detection first
        String? foundCategory;
        String finalType = 'expense';
        
        for (final entry in _merchantCategoryMap.entries) {
          if (lower.contains(entry.key)) {
            foundCategory = entry.value;
            finalType = 'expense'; // merchants typically indicate expenses
            break;
          }
        }

        // Ensure custom categories are loaded and check their keywords
        if (!_customLoaded) {
          await reloadCustomCategories();
        }
        
        // Custom categories take precedence over merchant detection
        if (foundCategory == null) {
          for (final cat in _customCategoriesCache) {
            final kwStr = (cat.keywords ?? '').toLowerCase();
            if (kwStr.isEmpty) continue;
            final kws = kwStr.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
            for (final kw in kws) {
              if (lower.contains(kw)) {
                foundCategory = cat.name;
                finalType = cat.type;
                break;
              }
            }
            if (foundCategory != null) break;
          }
        }

        // fallback to built-in category map
        if (foundCategory == null) {
          for (final entry in _categoryMap) {
            final keywords = (entry['keywords'] as List).cast<String>();
            for (final kw in keywords) {
              if (lower.contains(kw)) {
                foundCategory = entry['category'] as String;
                finalType = entry['type'] as String;
                break;
              }
            }
            if (foundCategory != null) break;
          }
        }

        // If the user explicitly indicates the source is savings (paid from savings),
        // treat this transaction as type 'saving' (reduces saving) rather than expense from income.
        final usedSavingPhrases = ['dari tabungan', 'pakai tabungan', 'ambil dari tabungan', 'dari simpanan', 'pakai simpanan', 'tabungan', 'tabung', 'simpan', 'setor', 'menabung', 'tarik dari tabungan'];
        if (usedSavingPhrases.any((p) => lower.contains(p))) {
          finalType = 'saving';
        }

        // detect shared/personal scope
        final sharedKeywords = ['bersama', 'patungan', 'split', 'split bill', 'share', 'barengan', 'bagi', 'bayar bersama', 'patungan dengan', 'bersama-sama', 'keluarga', 'teman', 'bersama teman'];
        final personalKeywords = ['pribadi', 'sendiri', 'untuk saya', 'personal'];
        String finalScope = 'personal';
        if (sharedKeywords.any((p) => lower.contains(p))) {
          finalScope = 'shared';
        } else if (personalKeywords.any((p) => lower.contains(p))) {
          finalScope = 'personal';
        }

        // fallback category detection
        String? category;
        if (foundCategory != null) {
          category = foundCategory;
        } else if (lower.contains('makan') || lower.contains('beli') || lower.contains('belanja')) {
          category = 'Belanja';
        } else if (likelySaving) {
          category = 'Saving';
        }

        if (finalType == 'saving' && category == null) {
          category = 'Tabungan';
        }

        // determine isIncome: prefer explicit mapping, otherwise use heuristic
        final isIncome = finalType == 'income' ? true : (finalType == 'saving' ? false : likelyIncome && !likelyExpense);

        return ParsedTransaction(amount: amount, currency: 'IDR', category: category, description: text, isIncome: isIncome, type: finalType, scope: finalScope);
      }
    } catch (e) {
      // ignore parsing errors for scaffold
    }
    return null;
  }

  Future<Map<String, dynamic>?> parseDeleteIntent(String text) async {
    final lower = text.toLowerCase();
    if (!lower.contains('hapus') && !lower.contains('delete') && !lower.contains('hapuskan')) return null;

    // match "hapus 3 transaksi terakhir"
    final lastMatch = RegExp(r'hapus\s+(\d+)\s+transaksi\s+terakhir').firstMatch(lower);
    if (lastMatch != null) {
      final n = int.tryParse(lastMatch.group(1) ?? '0') ?? 0;
      if (n > 0) return {'mode': 'last', 'count': n};
    }

    // match "hapus transaksi terakhir" or "hapus terakhir" -> default to 1
    final lastImplicit = RegExp(r'hapus(?:\s+transaksi)?\s+(?:yang\s+)?terakhir').firstMatch(lower);
    if (lastImplicit != null) {
      return {'mode': 'last', 'count': 1};
    }

    // match "hapus transaksi 09/08(/2025)" or "hapus 09-08-2025"
    final numericDate = RegExp(r'hapus(?:\s+transaksi)?\s+(\d{1,2})[\/\-](\d{1,2})(?:[\/\-](\d{4}))?');
    final mNum = numericDate.firstMatch(lower);
    if (mNum != null) {
      final d = int.tryParse(mNum.group(1) ?? '0') ?? 0;
      final m = int.tryParse(mNum.group(2) ?? '0') ?? 0;
      final y = int.tryParse(mNum.group(3) ?? '${DateTime.now().year}') ?? DateTime.now().year;
      if (d > 0 && m > 0) {
        final start = DateTime(y, m, d);
        final end = start.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
        return {'mode': 'range', 'start': start, 'end': end};
      }
    }

    // match period keywords like "hari ini", "kemarin", "bulan lalu"
    final now = DateTime.now();
    if (lower.contains('hari ini') || lower.contains('today')) {
      final start = DateTime(now.year, now.month, now.day);
      final end = start.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
      return {'mode': 'range', 'start': start, 'end': end};
    }
    if (lower.contains('kemarin') || lower.contains('yesterday')) {
      final day = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
      final start = DateTime(day.year, day.month, day.day);
      final end = start.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
      return {'mode': 'range', 'start': start, 'end': end};
    }
    if (lower.contains('bulan ini') || lower.contains('this month')) {
      final start = DateTime(now.year, now.month, 1);
      final end = DateTime(now.year, now.month + 1, 1).subtract(const Duration(milliseconds: 1));
      return {'mode': 'range', 'start': start, 'end': end};
    }

    // match "hapus seluruh transaksi" or "hapus semua transaksi" -> all transactions
    if (lower.contains('seluruh transaksi') || lower.contains('semua transaksi') || lower.contains('hapus semua')) {
      return {'mode': 'all'};
    }

    return null;
  }

  // --- New: Rule-based intent parser to return structured intents for the chat UI ---
  Future<Map<String, dynamic>> parseIntent(String text) async {
    final lower = text.toLowerCase().trim();

    // 1) delete intent (explicit)
    final deleteSpec = await parseDeleteIntent(text);
    if (deleteSpec != null) {
      return {
        'intent': 'delete',
        'confidence': 0.95,
        'delete': deleteSpec,
        'raw': text,
      };
    }

    // 2) check for summary/list intents
    final wantsSummary = ['ringkasan', 'total', 'berapa', 'pendapatan', 'pengeluaran', 'saldo'].any((k) => lower.contains(k));
    final wantsList = ['daftar', 'tampilkan', 'catatan', 'list', 'show', 'lihat'].any((k) => lower.contains(k));

    // 3) attempt to parse period from text (basic)
    Map<String, dynamic> parsePeriod(String input) {
      final now = DateTime.now();
      if (input.contains('hari ini') || input.contains('today')) {
        final start = DateTime(now.year, now.month, now.day);
        final end = start.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
        return {'isPeriod': true, 'start': start, 'end': end, 'label': 'hari ini', 'periodKey': 'day'};
      }
      if (input.contains('kemarin') || input.contains('yesterday')) {
        final d = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
        final start = DateTime(d.year, d.month, d.day);
        final end = start.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
        return {'isPeriod': true, 'start': start, 'end': end, 'label': 'kemarin', 'periodKey': 'day'};
      }
      if (input.contains('bulan ini') || input.contains('this month')) {
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month + 1, 1).subtract(const Duration(milliseconds: 1));
        return {'isPeriod': true, 'start': start, 'end': end, 'label': 'bulan ini', 'periodKey': 'month'};
      }

      // numeric date dd/mm[/yyyy]
      final numericDate = RegExp(r'(?:pada\s*)?(\d{1,2})[\/\-](\d{1,2})(?:[\/\-](\d{4}))?');
      final m = numericDate.firstMatch(input);
      if (m != null) {
        final d = int.tryParse(m.group(1) ?? '0') ?? 0;
        final mm = int.tryParse(m.group(2) ?? '0') ?? 0;
        final yy = int.tryParse(m.group(3) ?? '${now.year}') ?? now.year;
        if (d > 0 && mm > 0) {
          final start = DateTime(yy, mm, d);
          final end = start.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
          return {'isPeriod': true, 'start': start, 'end': end, 'label': '${d.toString().padLeft(2,'0')}/${mm.toString().padLeft(2,'0')}/${yy}', 'periodKey': 'day'};
        }
      }

      return {'isPeriod': false};
    }

    final period = parsePeriod(lower);

    // If the user explicitly asked for a list or summary, prioritize that intent
    if (wantsList || wantsSummary) {
      // extract optional count for list requests, e.g. 'daftar 10 transaksi terakhir'
      int? extractCount(String s) {
        final m = RegExp(r'(?:daftar|tampilkan)\s+(\d{1,3})').firstMatch(s);
        if (m != null) return int.tryParse(m.group(1) ?? '0');
        // also support word numbers like 'daftar sepuluh' (basic)
        final wordMatch = RegExp(r'(?:daftar|tampilkan)\s+([a-z\-\s]+)\s+transaksi').firstMatch(s);
        if (wordMatch != null) {
          final w = (wordMatch.group(1) ?? '').trim();
          // simple mapping for common words
          final map = {'satu':1,'dua':2,'tiga':3,'empat':4,'lima':5,'enam':6,'tujuh':7,'delapan':8,'sembilan':9,'sepuluh':10};
          if (map.containsKey(w)) return map[w];
        }
        return null;
      }

      if (wantsList) {
        final count = extractCount(lower) ?? 10; // default 10
        return {
          'intent': 'list',
          'confidence': 0.9,
          'period': period,
          'count': count,
          'raw': text,
        };
      }

      if (wantsSummary) {
        return {
          'intent': 'summary',
          'confidence': 0.9,
          'period': period,
          'raw': text,
        };
      }
    }

    // 4) parse transactions (single or batch) -- only if not explicitly asking for list/summary
    final parts = text.split(RegExp(r'[,;\n\\/\|]|\bdan\b|\band\b', caseSensitive: false)).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final parsedList = <ParsedTransaction>[];
    for (final p in parts) {
      final pParsed = await parseText(p);
      if (pParsed != null) parsedList.add(pParsed);
    }

    if (parsedList.isNotEmpty) {
      // if any parsed transaction is shared, attempt to ensure a group exists and include groupId
      String? groupId;
      try {
        final anyShared = parsedList.any((p) => p.scope == 'shared');
        if (anyShared) {
          groupId = await _getOrCreateGroupForText(text);
        }
      } catch (_) {
        groupId = null;
      }

      return {
        'intent': 'create',
        'confidence': 0.9,
        'transactions': parsedList,
        'period': period,
        'groupId': groupId,
        'raw': text,
      };
    }

    // 6) fallback: return unknown with low confidence
    return {'intent': 'unknown', 'confidence': 0.3, 'raw': text};
  }

}
