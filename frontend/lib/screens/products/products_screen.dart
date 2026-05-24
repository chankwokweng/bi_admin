import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../widgets/error_banner.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  List<Map<String, dynamic>> _items = [];
  List<String> _categories = [];
  int _total = 0;
  int _page = 1;
  static const _pageSize = 20;

  String _search = '';
  String _category = '';
  bool _loading = false;
  String? _error;

  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final data = await ApiService.get('/products/categories');
      setState(() => _categories = List<String>.from(data));
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final params = <String, String>{
        'page': '$_page',
        'page_size': '$_pageSize',
        if (_search.isNotEmpty) 'search': _search,
        if (_category.isNotEmpty) 'category': _category,
      };
      final data = await ApiService.get('/products', params: params);
      setState(() {
        _items = List<Map<String, dynamic>>.from(data['items']);
        _total = data['total'];
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilters() {
    _page = 1;
    _load();
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ProductEditDialog(row: row),
    );
    if (result == null) return;
    try {
      await ApiService.put('/products/${row['id']}', result);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = (_total / _pageSize).ceil().clamp(1, 999);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Products', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          // Filters
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Search name or SKU…',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                  onSubmitted: (_) => _applyFilters(),
                  onChanged: (v) => _search = v,
                ),
              ),
              const SizedBox(width: 12),
              DropdownMenu<String>(
                initialSelection: '',
                label: const Text('Category'),
                onSelected: (v) { _category = v ?? ''; _applyFilters(); },
                dropdownMenuEntries: [
                  const DropdownMenuEntry(value: '', label: 'All'),
                  ..._categories.map((c) => DropdownMenuEntry(value: c, label: c)),
                ],
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _applyFilters, child: const Text('Search')),
              const SizedBox(width: 8),
              IconButton(icon: const Icon(Icons.refresh), onPressed: _load, tooltip: 'Refresh'),
            ],
          ),
          const SizedBox(height: 12),
          if (_error != null) ErrorBanner(message: _error!),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(const Color(0xFFE8EAF6)),
                  columnSpacing: 16,
                  columns: const [
                    DataColumn(label: Text('Name')),
                    DataColumn(label: Text('SKU')),
                    DataColumn(label: Text('Category')),
                    DataColumn(label: Text('Subcategory')),
                    DataColumn(label: Text('Selling Price'), numeric: true),
                    DataColumn(label: Text('Cost Price'), numeric: true),
                    DataColumn(label: Text('Translated SKU')),
                    DataColumn(label: Text('Translated Category')),
                    DataColumn(label: Text('')),
                  ],
                  rows: _items.map((r) {
                    return DataRow(cells: [
                      DataCell(Text(r['name'] ?? '')),
                      DataCell(Text(r['sku_code'] ?? '')),
                      DataCell(Text(r['category'] ?? '')),
                      DataCell(Text(r['subcategory'] ?? '')),
                      DataCell(Text(_fmt(r['selling_price']))),
                      DataCell(Text(_fmt(r['cost_price']))),
                      DataCell(Text(r['translated_sku_code'] ?? '')),
                      DataCell(Text(r['translated_category'] ?? '')),
                      DataCell(IconButton(
                        icon: const Icon(Icons.edit, size: 18),
                        onPressed: () => _edit(r),
                      )),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          // Pagination
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Page $_page of $totalPages  |  $_total results'),
              const SizedBox(width: 16),
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _page > 1 ? () { _page--; _load(); } : null,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _page < totalPages ? () { _page++; _load(); } : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmt(dynamic val) {
    if (val == null) return '—';
    return double.tryParse(val.toString())?.toStringAsFixed(2) ?? val.toString();
  }
}

class _ProductEditDialog extends StatefulWidget {
  final Map<String, dynamic> row;
  const _ProductEditDialog({required this.row});

  @override
  State<_ProductEditDialog> createState() => _ProductEditDialogState();
}

class _ProductEditDialogState extends State<_ProductEditDialog> {
  late final TextEditingController _category;
  late final TextEditingController _subcategory;
  late final TextEditingController _sellingPrice;
  late final TextEditingController _costPrice;
  late final TextEditingController _translatedSku;
  late final TextEditingController _translatedCategory;

  @override
  void initState() {
    super.initState();
    _category = TextEditingController(text: widget.row['category'] ?? '');
    _subcategory = TextEditingController(text: widget.row['subcategory'] ?? '');
    _sellingPrice = TextEditingController(text: widget.row['selling_price']?.toString() ?? '');
    _costPrice = TextEditingController(text: widget.row['cost_price']?.toString() ?? '');
    _translatedSku = TextEditingController(text: widget.row['translated_sku_code'] ?? '');
    _translatedCategory = TextEditingController(text: widget.row['translated_category'] ?? '');
  }

  @override
  void dispose() {
    for (final c in [_category, _subcategory, _sellingPrice, _costPrice, _translatedSku, _translatedCategory]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit — ${widget.row['name']}'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field('Category', _category),
              _field('Subcategory', _subcategory),
              _field('Selling Price', _sellingPrice, numeric: true),
              _field('Cost Price', _costPrice, numeric: true),
              _field('Translated SKU Code', _translatedSku),
              _field('Translated Category', _translatedCategory),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, {
            if (_category.text.isNotEmpty) 'category': _category.text,
            if (_subcategory.text.isNotEmpty) 'subcategory': _subcategory.text,
            if (_sellingPrice.text.isNotEmpty) 'selling_price': double.tryParse(_sellingPrice.text),
            if (_costPrice.text.isNotEmpty) 'cost_price': double.tryParse(_costPrice.text),
            if (_translatedSku.text.isNotEmpty) 'translated_sku_code': _translatedSku.text,
            if (_translatedCategory.text.isNotEmpty) 'translated_category': _translatedCategory.text,
          }),
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _field(String label, TextEditingController ctrl, {bool numeric = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
      ),
    );
  }
}
