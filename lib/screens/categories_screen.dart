import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:catatan_keuangan_pintar/services/db_service.dart';
import 'package:catatan_keuangan_pintar/services/parser_service.dart';
import 'package:catatan_keuangan_pintar/services/fasttext_service.dart';
import 'package:catatan_keuangan_pintar/services/builtin_categories.dart';
import 'package:catatan_keuangan_pintar/widgets/hint_widgets.dart';
class CategoriesScreen extends StatefulWidget {
  final String? accountId;
  final String? accountName;
  
  const CategoriesScreen({super.key, this.accountId, this.accountName});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  final _uuid = const Uuid();
  List<Category> _cats = [];
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim().toLowerCase());
    });
    
    // Show first-time setup dialog if no categories exist for this account
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndShowSetupDialog());
  }

  Future<void> _checkAndShowSetupDialog() async {
    if (widget.accountId == null) return; // Only for account-specific view
    
    final accountCategories = await DBService.instance.getCategories(accountId: widget.accountId);
    final hasAccountSpecificCategories = accountCategories.any((c) => c.accountId == widget.accountId);
    
    if (!hasAccountSpecificCategories) {
      if (mounted) {
        _showFirstTimeSetupDialog();
      }
    }
  }

  Future<void> _showFirstTimeSetupDialog() async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Atur Kategori'),
        content: Text(
          widget.accountName != null
              ? 'Belum ada kategori untuk ${widget.accountName}. Apakah Anda ingin membuat kategori otomatis atau membuat sendiri?'
              : 'Belum ada kategori untuk akun ini. Apakah Anda ingin membuat kategori otomatis atau membuat sendiri?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('manual'),
            child: const Text('Buat Sendiri'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop('auto'),
            child: const Text('Buat Otomatis'),
          ),
        ],
      ),
    );

    if (result == 'auto' && widget.accountId != null) {
      await _autoCreateCategories(widget.accountId!);
      _load();
    }
  }

  Future<void> _autoCreateCategories(String accountId) async {
    // Create basic categories for the account
    final now = DateTime.now();
    final basicCategories = [
      Category(id: '${_uuid.v4()}', name: 'Belanja', type: 'expense', keywords: 'belanja,groceries,supermarket', accountId: accountId, createdAt: now),
      Category(id: '${_uuid.v4()}', name: 'Transportasi', type: 'expense', keywords: 'transport,ojek,bensin,parkir', accountId: accountId, createdAt: now),
      Category(id: '${_uuid.v4()}', name: 'Makan & Minum', type: 'expense', keywords: 'makan,minum,restoran,kafe', accountId: accountId, createdAt: now),
      Category(id: '${_uuid.v4()}', name: 'Gaji', type: 'income', keywords: 'gaji,salary,tunjangan', accountId: accountId, createdAt: now),
      Category(id: '${_uuid.v4()}', name: 'Bonus', type: 'income', keywords: 'bonus,insentif,komisi', accountId: accountId, createdAt: now),
      Category(id: '${_uuid.v4()}', name: 'Tabungan', type: 'saving', keywords: 'tabung,tabungan,simpan', accountId: accountId, createdAt: now),
    ];
    
    for (final cat in basicCategories) {
      await DBService.instance.insertCategory(cat);
    }
    
    await ParserService.instance.reloadCustomCategories();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kategori otomatis berhasil dibuat')),
      );
    }
  }

  Future<void> _load() async {
    final rows = await DBService.instance.getCategories(accountId: widget.accountId);
    if (rows.isEmpty) {
      // seed defaults when DB has no categories (upgrade path may have created table without seeds)
      await DBService.instance.insertCategory(Category(id: 'c_groceries', name: 'Groceries', type: 'expense', keywords: 'belanja,groceries,sebako', createdAt: DateTime.now()));
      await DBService.instance.insertCategory(Category(id: 'c_salary', name: 'Gaji', type: 'income', keywords: 'gaji,tunjangan', createdAt: DateTime.now()));
      await DBService.instance.insertCategory(Category(id: 'c_saving', name: 'Tabungan', type: 'saving', keywords: 'tabungan,tabung,simpan', createdAt: DateTime.now()));
      await DBService.instance.insertCategory(Category(id: 'c_invest', name: 'Investasi', type: 'investment', keywords: 'investasi,saham,reksadana', createdAt: DateTime.now()));
      await ParserService.instance.reloadCustomCategories();
      final refreshed = await DBService.instance.getCategories(accountId: widget.accountId);
      setState(() => _cats = refreshed);
      return;
    }
    setState(() => _cats = rows);
  }

  Future<void> _showEditor({Category? c}) async {
    final nameCtrl = TextEditingController(text: c?.name ?? '');
    String typeVar = c?.type ?? 'expense';
    final kwCtrl = TextEditingController(text: c?.keywords ?? '');

    // initial lightweight suggestions from DB (non-blocking)
    List<String> initialSuggestions = [];
    try {
      initialSuggestions = await DBService.instance.topTokensForCategory(c?.name, limit: 8);
    } catch (_) {}

  bool sheetActive = true;
  await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
  builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: StatefulBuilder(
            builder: (ctx2, setStateDialog) {
              // safe wrapper to avoid calling setState on disposed builder
              void safeSetStateDialog(VoidCallback fn) {
                try {
                  setStateDialog(fn);
                } catch (_) {
                  // ignore - sheet likely disposed
                }
              }
              // suggestion local state
              List<String> suggestionsLocal = List<String>.from(initialSuggestions);
              bool loading = false;

              // debounce timer to avoid firing many concurrent requests while typing
              Timer? _debounce;
              // simple in-memory cache for recent inputs (per bottom-sheet lifetime)
              final Map<String, List<String>> _suggestionCache = {};
              // request counter to drop stale results
              int _latestReq = 0;

              Future<void> computeSuggestions(String nameText, String typeKey) async {
                final cacheKey = '${nameText.trim().toLowerCase()}|$typeKey';

                // return cached result synchronously if available
                if (_suggestionCache.containsKey(cacheKey)) {
                  setStateDialog(() => suggestionsLocal = List<String>.from(_suggestionCache[cacheKey]!));
                  return;
                }

                setStateDialog(() => loading = true);
                final int myReq = ++_latestReq;
                final temp = <String>[];
                try {
                  // DB tokens (history-based) - non-fatal
                  try {
                    final dbTokens = await DBService.instance.topTokensForCategory(nameText, limit: 8);
                    temp.addAll(dbTokens.where((t) => t.isNotEmpty));
                  } catch (e) {
                    debugPrint('computeSuggestions: topTokensForCategory failed: $e');
                  }

                  // tokens from name (always useful for new words)
                  final baseName = nameText.trim();
                  if (baseName.isNotEmpty) {
                    final nameTokens = baseName.toLowerCase().split(RegExp(r"[^a-z0-9]+")).where((s) => s.length >= 2).toList();
                    for (final t in nameTokens) {
                      if (!temp.contains(t)) temp.add(t);
                    }
                  }

                  // builtin keywords for type
                  try {
                    final builtinForType = BUILTIN_CATEGORIES.where((e) => e['type'] == typeKey);
                    for (final e in builtinForType) {
                      final kws = (e['keywords'] as List).cast<String>();
                      for (final k in kws) {
                        final low = k.toLowerCase().trim();
                        if (!temp.contains(low)) temp.add(low);
                      }
                    }
                  } catch (e) {
                    debugPrint('computeSuggestions: builtin keywords failed: $e');
                  }

                  // lightweight model predictions (optional)
                  try {
                    if (nameText.isNotEmpty) {
                      final preds = await FastTextService.instance.predict(nameText, k: 3);
                      for (final p in preds) {
                        final lbl = (p['label'] as String).toLowerCase();
                        if (!temp.contains(lbl)) temp.add(lbl);
                      }
                    }
                  } catch (e) {
                    debugPrint('computeSuggestions: fasttext predict failed: $e');
                  }

                  // keep list short
                  if (temp.length > 12) temp.removeRange(12, temp.length);

                  // fallback: if nothing found, prefer initial suggestions so UI shows something
                  if (temp.isEmpty && initialSuggestions.isNotEmpty) {
                    temp.addAll(initialSuggestions);
                  }

                  // If this result is still the latest request, apply it; otherwise drop it (avoids race loops)
                  if (sheetActive && myReq == _latestReq) {
                    _suggestionCache[cacheKey] = List<String>.from(temp);
                    safeSetStateDialog(() {
                      suggestionsLocal = List<String>.from(temp);
                    });
                  } else {
                    // cache stale result for future quick access, but don't set UI
                    _suggestionCache[cacheKey] = List<String>.from(temp);
                  }
                } catch (e, st) {
                  debugPrint('computeSuggestions: unexpected error $e\n$st');
                } finally {
                  // only clear loading if this was the latest
                  if (sheetActive && myReq == _latestReq) safeSetStateDialog(() => loading = false);
                }
              }

              void scheduleCompute(String nameText, String typeKey) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), () => computeSuggestions(nameText, typeKey));
              }

              // initial compute (use cached path if possible)
              scheduleCompute(nameCtrl.text, typeVar);

              // ensure we cancel timers when sheet is closed by wrapping Navigator pop
              void _onCloseCleanup() {
                _debounce?.cancel();
                sheetActive = false;
              }

              return SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text(c == null ? 'Tambah Kategori' : 'Edit Kategori', style: Theme.of(context).textTheme.titleLarge),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(ctx).pop()),
                      ]),
                      const SizedBox(height: 8),
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(labelText: 'Nama', border: OutlineInputBorder()),
                        onChanged: (v) => scheduleCompute(v, typeVar),
                      ),
                      const SizedBox(height: 12),
                      InputDecorator(
                        decoration: const InputDecoration(labelText: 'Tipe', border: OutlineInputBorder()),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: typeVar,
                            items: const [
                              DropdownMenuItem(value: 'expense', child: Text('Pengeluaran')),
                              DropdownMenuItem(value: 'income', child: Text('Pendapatan')),
                              DropdownMenuItem(value: 'saving', child: Text('Tabungan')),
                              DropdownMenuItem(value: 'investment', child: Text('Investasi')),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              setStateDialog(() => typeVar = v);
                              scheduleCompute(nameCtrl.text, v);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(controller: kwCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Kata kunci (pisah koma)', border: OutlineInputBorder())),
                      const SizedBox(height: 8),
                      if (loading) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Center(child: SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)))),
                      if (suggestionsLocal.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text('Saran kata kunci', style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: suggestionsLocal.map((s) => ActionChip(
                            label: Text(s, style: const TextStyle(fontSize: 12)),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            onPressed: () {
                              final current = kwCtrl.text.trim();
                              final parts = current.isEmpty ? <String>[] : current.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
                              if (!parts.contains(s)) parts.add(s);
                              kwCtrl.text = parts.join(', ');
                            },
                          )).toList(),
                        ),
                        const SizedBox(height: 8),
                        Row(children: [
                          OutlinedButton(onPressed: () { kwCtrl.text = suggestionsLocal.join(', '); }, child: const Text('Isi Otomatis')),
                          const SizedBox(width: 8),
                          OutlinedButton(onPressed: () { final cur = kwCtrl.text.trim(); kwCtrl.text = cur.isEmpty ? suggestionsLocal.join(', ') : '$cur, ${suggestionsLocal.join(', ')}'; }, child: const Text('Tambahkan Semua')),
                        ]),
                        const SizedBox(height: 8),
                      ],
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(child: OutlinedButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Batal'))),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              final id = c?.id ?? _uuid.v4();
                              final cat = Category(
                                id: id, 
                                name: nameCtrl.text.trim(), 
                                type: typeVar, 
                                keywords: kwCtrl.text.trim(), 
                                accountId: widget.accountId, // Link to account if viewing account-specific categories
                                createdAt: DateTime.now(),
                              );
                              await DBService.instance.insertCategory(cat);
                              await ParserService.instance.reloadCustomCategories();
                              Navigator.of(ctx).pop();
                              _load();
                            },
                            child: const Text('Simpan'),
                          ),
                        ),
                      ])
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.accountName != null 
              ? 'Kategori - ${widget.accountName}' 
              : 'Manajemen Kategori',
        ),
        actions: [
          HintIcon(
            title: 'Tentang Kategori',
            message: 'Kategori membantu Anda mengorganisir transaksi. '
                'Anda bisa membuat kategori custom atau menggunakan kategori otomatis. '
                'Kategori dapat dibuat spesifik untuk setiap akun/dompet atau dibuat global. '
                'Gunakan kata kunci untuk membantu sistem mengenali transaksi secara otomatis.',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Cari kategori atau kata kunci...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchCtrl.clear(); })
                      : null,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeOutQuart,
                switchOutCurve: Curves.easeInQuart,
                child: ListView(
                  key: ValueKey(_query),
                  padding: const EdgeInsets.only(bottom: 80),
                  children: [
                    _buildGroup('income', 'Pendapatan'),
                    _buildGroup('expense', 'Pengeluaran'),
                    _buildGroup('saving', 'Tabungan'),
                    _buildGroup('investment', 'Investasi'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditor(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildGroup(String typeKey, String title) {
    final items = _cats.where((c) {
      if (c.type != typeKey) return false;
      if (_query.isEmpty) return true;
      final name = c.name.toLowerCase();
      final kws = c.keywords.toLowerCase();
      return name.contains(_query) || kws.contains(_query);
    }).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('$title', style: Theme.of(context).textTheme.titleMedium),
                Text('(${items.length})', style: Theme.of(context).textTheme.bodySmall),
              ]),
              const SizedBox(height: 8),
              if (items.isEmpty)
                Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('Tidak ada kategori.', style: Theme.of(context).textTheme.bodySmall))
              else
                ...items.map((c) {
                  final kwList = c.keywords.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
                  return Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: kwList.isEmpty
                            ? null
                            : Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: kwList
                                      .map((k) => Chip(
                                            label: Text(k, style: const TextStyle(fontSize: 12)),
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            visualDensity: VisualDensity.compact,
                                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          ))
                                      .toList(),
                                ),
                              ),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blueAccent),
                            onPressed: () => _showEditor(c: c),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.redAccent),
                            onPressed: () async {
                              await DBService.instance.deleteCategory(c.id);
                              await ParserService.instance.reloadCustomCategories();
                              _load();
                            },
                          ),
                        ]),
                      ),
                      const Divider(height: 1),
                    ],
                  );
                }).toList(),
            ],
          ),
        ),
      ),
    );
  }
}
