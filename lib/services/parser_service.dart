import 'dart:async';
import 'package:catatan_keuangan_pintar/services/db_service.dart';
import 'package:catatan_keuangan_pintar/services/auth_service.dart';
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
  final String? accountId; // Account ID for the transaction
  final String? accountName; // Account name mentioned in text

  ParsedTransaction({
    required this.amount,
    this.currency,
    this.category,
    this.description,
    this.date,
    this.isIncome = false,
    this.type = 'expense',
    this.scope = 'personal',
    this.accountId,
    this.accountName,
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
    final newGroup = Group(
      id: id,
      name: baseName,
      description: null,
      icon: null,
      createdAt: DateTime.now(),
      createdBy: AuthService.instance.userId,
    );
    await DBService.instance.insertGroup(newGroup);
    return id;
  }

  // use BUILTIN_CATEGORIES from builtin_categories.dart
  final List<Map<String, Object>> _categoryMap = BUILTIN_CATEGORIES;

  String? _matchCategoryByName(String input) {
    final needle = input.toLowerCase().trim();
    if (needle.isEmpty) return null;
    for (final cat in _customCategoriesCache) {
      if (cat.name.toLowerCase() == needle) return cat.name;
    }
    for (final entry in _categoryMap) {
      final name = (entry['category'] as String).toLowerCase();
      if (name == needle) return entry['category'] as String;
    }
    return null;
  }

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

    // Handle quantity x price (e.g., "2x 15000", "3 x 15rb")
    final qtyMatch = RegExp(r'(\d+)\s*[x×]\s*(\d+(?:[.,]\d+)?)(\s*(?:rb|ribu|k|jt|juta|m|miliar|milyar|b))?', caseSensitive: false).firstMatch(lower);
    if (qtyMatch != null) {
      final qty = int.tryParse(qtyMatch.group(1) ?? '0') ?? 0;
      final base = double.tryParse((qtyMatch.group(2) ?? '0').replaceAll(',', '.')) ?? 0;
      final suffix = (qtyMatch.group(3) ?? '').trim().toLowerCase();
      double unit = base;
      if (suffix.contains('rb') || suffix.contains('ribu') || suffix == 'k') unit = base * 1000;
      if (suffix.contains('jt') || suffix.contains('juta') || suffix == 'm') unit = base * 1000000;
      if (suffix.contains('miliar') || suffix.contains('milyar') || suffix == 'b') unit = base * 1000000000;
      final total = qty * unit;
      if (total > 0) return total;
    }
    
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

  DateTime? _parseDate(String text) {
    final lower = text.toLowerCase();
    final now = DateTime.now();
    if (lower.contains('hari ini')) return DateTime(now.year, now.month, now.day);
    if (lower.contains('kemarin')) {
      final d = now.subtract(const Duration(days: 1));
      return DateTime(d.year, d.month, d.day);
    }
    if (lower.contains('besok')) {
      final d = now.add(const Duration(days: 1));
      return DateTime(d.year, d.month, d.day);
    }
    if (lower.contains('lusa')) {
      final d = now.add(const Duration(days: 2));
      return DateTime(d.year, d.month, d.day);
    }

    final numeric = RegExp(r'(\d{1,2})[\/\-](\d{1,2})(?:[\/\-](\d{2,4}))?');
    final m = numeric.firstMatch(lower);
    if (m != null) {
      final d = int.tryParse(m.group(1) ?? '0') ?? 0;
      final mo = int.tryParse(m.group(2) ?? '0') ?? 0;
      int y = int.tryParse(m.group(3) ?? '') ?? now.year;
      if (y < 100) y = 2000 + y;
      if (d > 0 && mo > 0) {
        return DateTime(y, mo, d);
      }
    }

    final monthMap = {
      'jan': 1, 'januari': 1,
      'feb': 2, 'februari': 2,
      'mar': 3, 'maret': 3,
      'apr': 4, 'april': 4,
      'mei': 5,
      'jun': 6, 'juni': 6,
      'jul': 7, 'juli': 7,
      'agu': 8, 'agustus': 8,
      'sep': 9, 'september': 9,
      'okt': 10, 'oktober': 10,
      'nov': 11, 'november': 11,
      'des': 12, 'desember': 12,
    };
    final named = RegExp(r'(\d{1,2})\s+([a-z]+)\s*(\d{2,4})?');
    final m2 = named.firstMatch(lower);
    if (m2 != null) {
      final d = int.tryParse(m2.group(1) ?? '0') ?? 0;
      final mo = monthMap[m2.group(2) ?? ''];
      int y = int.tryParse(m2.group(3) ?? '') ?? now.year;
      if (y < 100) y = 2000 + y;
      if (d > 0 && mo != null) {
        return DateTime(y, mo, d);
      }
    }

    return null;
  }

  Future<ParsedTransaction?> parseText(String text) async {
    // Enhanced rule-based parsing with merchant detection and Indonesian number format
    try {
      final lower = text.toLowerCase();
      final parsedDate = _parseDate(text);

      // detect income keywords
      final incomeKeywords = ['dapat', 'terima', 'bonus', 'gaji', 'masuk', 'menerima', 'terima uang', 'gajian', 'honorarium', 'upah', 'penghasilan', 'komisi', 'dividen', 'refund', 'cashback'];
      final expenseKeywords = ['beli', 'bayar', 'makan', 'bensin', 'roti', 'sembako', 'pakai', 'keluar', 'belanja', 'transfer', 'kirim', 'top up', 'isi ulang', 'langganan'];
      final savingKeywords = ['tabungan', 'dana darurat', 'savings', 'tabung', 'simpan', 'setor', 'menabung'];
      final investmentKeywords = ['investasi', 'reksadana', 'saham', 'obligasi', 'deposito'];

      bool likelyIncome = incomeKeywords.any((k) => lower.contains(k));
      bool likelyExpense = expenseKeywords.any((k) => lower.contains(k));
      bool likelySaving = savingKeywords.any((k) => lower.contains(k));
      bool likelyInvestment = investmentKeywords.any((k) => lower.contains(k));

      // Use enhanced amount parser
      final amount = _parseAmount(text);
      if (amount != null && amount > 0) {
        // Check merchant/brand detection first
        String? foundCategory;
        String finalType = likelyInvestment ? 'investment' : (likelySaving ? 'saving' : 'expense');
        
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

        // explicit category mention: "kategori: listrik"
        final catHint = RegExp(r'kategori\s*[:=]?\s*([a-zA-Z\s]+)').firstMatch(lower);
        if (catHint != null) {
          final raw = catHint.group(1) ?? '';
          final matched = _matchCategoryByName(raw);
          if (matched != null) {
            foundCategory = matched;
          }
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
        if (investmentKeywords.any((p) => lower.contains(p))) {
          finalType = 'investment';
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
        if (finalType == 'investment' && category == null) {
          category = 'Investasi';
        }

        // Parse account/sumber dana mentions (including savings)
        String? accountName;
        String? accountId;
        final accountKeywords = ['dari', 'pakai', 'gunakan', 'lewat', 'via', 'melalui', 'dengan'];
        for (final keyword in accountKeywords) {
          // Try to extract account name after keyword
          // Pattern: "keyword [account_name]"
          final pattern = RegExp('$keyword\\s+([a-zA-Z0-9\\s]+?)(?:\\s+(?:beli|bayar|untuk|ke|\\d+)|\\s*\$)', caseSensitive: false);
          final match = pattern.firstMatch(text);
          if (match != null) {
            final candidate = match.group(1)?.trim();
            if (candidate != null && candidate.length > 2) {
              // Check if this matches any known account (including savings)
              final accounts = await DBService.instance.getAccountsWithSavings();
              for (final acc in accounts) {
                if (acc.name.toLowerCase().contains(candidate.toLowerCase()) || 
                    candidate.toLowerCase().contains(acc.name.toLowerCase())) {
                  accountName = acc.name;
                  accountId = acc.id;
                  break;
                }
              }
              if (accountId == null && candidate.isNotEmpty) {
                // Store the mentioned name even if not found in accounts
                accountName = candidate;
              }
              break;
            }
          }
        }

        // determine isIncome: prefer explicit mapping, otherwise use heuristic
        final isIncome = finalType == 'income' ? true : (finalType == 'saving' || finalType == 'investment' ? false : likelyIncome && !likelyExpense);

        // split bill: "patungan 3 orang" + "per orang"/"masing-masing" -> divide amount
        final splitCountMatch = RegExp(r'(?:patungan|split)\s*(\d{1,2})\s*(?:orang|org|pax)').firstMatch(lower);
        if (splitCountMatch != null && (lower.contains('per orang') || lower.contains('masing-masing'))) {
          final n = int.tryParse(splitCountMatch.group(1) ?? '0') ?? 0;
          if (n > 1) {
            return ParsedTransaction(
              amount: amount / n,
              currency: 'IDR',
              category: category,
              description: text,
              isIncome: isIncome,
              type: finalType,
              scope: finalScope,
              date: parsedDate,
              accountId: accountId,
              accountName: accountName,
            );
          }
        }

        return ParsedTransaction(
          amount: amount,
          currency: 'IDR',
          category: category,
          description: text,
          isIncome: isIncome,
          type: finalType,
          scope: finalScope,
          date: parsedDate,
          accountId: accountId,
          accountName: accountName,
        );
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
    final parts = text
        .split(RegExp(r'[,;\n\\/\|]|\bdan\b|\band\b|\bkemudian\b|\blalu\b|\bterus\b|\bserta\b', caseSensitive: false))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
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
