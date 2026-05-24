import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../widgets/error_banner.dart';

class BomScreen extends StatefulWidget {
  const BomScreen({super.key});

  @override
  State<BomScreen> createState() => _BomScreenState();
}

class _BomScreenState extends State<BomScreen> {
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
      final data = await ApiService.get('/bom', params: params);
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

  void _applyFilters() { _page = 1; _load(); }

  Future<void> _openDetail(Map<String, dynamic> product) async {
    await showDialog(
      context: context,
      builder: (_) => _BomDetailDialog(product: product, onRefresh: _load),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = (_total / _pageSize).ceil().clamp(1, 999);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Bill of Materials', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Search product name or SKU…',
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
              child: ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (_, i) {
                  final item = _items[i];
                  final bomRows = List<Map<String, dynamic>>.from(item['bom_rows'] ?? []);
                  return Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: const Icon(Icons.inventory_2_outlined),
                      title: Text(item['product_name'] ?? item['product_sku_code'] ?? ''),
                      subtitle: Text('SKU: ${item['product_sku_code']}  |  ${item['product_category'] ?? ''}  |  ${bomRows.length} BOM rows'),
                      trailing: TextButton(
                        onPressed: () => _openDetail(item),
                        child: const Text('View / Edit BOM'),
                      ),
                    ),
                  );
                },
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Page $_page of $totalPages  |  $_total products'),
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
}

class _BomDetailDialog extends StatefulWidget {
  final Map<String, dynamic> product;
  final VoidCallback onRefresh;
  const _BomDetailDialog({required this.product, required this.onRefresh});

  @override
  State<_BomDetailDialog> createState() => _BomDetailDialogState();
}

class _BomDetailDialogState extends State<_BomDetailDialog> {
  late List<Map<String, dynamic>> _bomRows;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _bomRows = List<Map<String, dynamic>>.from(widget.product['bom_rows'] ?? []);
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final sku = widget.product['product_sku_code'];
      final data = await ApiService.get('/bom/$sku');
      setState(() => _bomRows = List<Map<String, dynamic>>.from(data['bom_rows']));
    } finally {
      if (mounted) setState(() => _loading = false);
      widget.onRefresh();
    }
  }

  Future<void> _addRow() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _BomRowDialog(
        usageSkuCode: widget.product['product_sku_code'],
      ),
    );
    if (result == null) return;
    try {
      await ApiService.post('/bom', result);
      _refresh();
    } catch (e) {
      if (mounted) _showError(e.toString());
    }
  }

  Future<void> _editRow(Map<String, dynamic> row) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _BomRowDialog(usageSkuCode: widget.product['product_sku_code'], existing: row),
    );
    if (result == null) return;
    try {
      await ApiService.put('/bom/${row['id']}', result);
      _refresh();
    } catch (e) {
      if (mounted) _showError(e.toString());
    }
  }

  Future<void> _deleteRow(Map<String, dynamic> row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete BOM row?'),
        content: Text('Delete "${row['raw_product']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    ) ?? false;
    if (!confirmed) return;
    try {
      await ApiService.delete('/bom/${row['id']}');
      _refresh();
    } catch (e) {
      if (mounted) _showError(e.toString());
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 900,
        height: 600,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.product['product_name'] ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text('SKU: ${widget.product['product_sku_code']}  |  ${widget.product['product_category'] ?? ''}',
                            style: TextStyle(color: Colors.grey[600])),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add Row'),
                    onPressed: _addRow,
                  ),
                  const SizedBox(width: 8),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const Divider(height: 20),
              if (_loading)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(const Color(0xFFE8EAF6)),
                      columnSpacing: 12,
                      columns: const [
                        DataColumn(label: Text('Raw Product')),
                        DataColumn(label: Text('Raw SKU')),
                        DataColumn(label: Text('Cost'), numeric: true),
                        DataColumn(label: Text('UOM')),
                        DataColumn(label: Text('Unit Qty'), numeric: true),
                        DataColumn(label: Text('BOM Qty'), numeric: true),
                        DataColumn(label: Text('BOM Cost'), numeric: true),
                        DataColumn(label: Text('BOM Qty/Unit'), numeric: true),
                        DataColumn(label: Text('Sort')),
                        DataColumn(label: Text('')),
                      ],
                      rows: _bomRows.map((r) {
                        return DataRow(cells: [
                          DataCell(Text(r['raw_product'] ?? '')),
                          DataCell(Text(r['raw_product_sku_code'] ?? '')),
                          DataCell(Text(_fmt(r['cost']))),
                          DataCell(Text(r['uom'] ?? '')),
                          DataCell(Text(_fmt(r['unit_qty_in_uom']))),
                          DataCell(Text(_fmt(r['bom_qty_in_uom']))),
                          DataCell(Text(_fmt(r['bom_cost']))),
                          DataCell(Text(_fmt(r['bom_qty_in_unit']))),
                          DataCell(Text(r['raw_product_sort_seq']?.toString() ?? '')),
                          DataCell(Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(icon: const Icon(Icons.edit, size: 16), onPressed: () => _editRow(r)),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                                onPressed: () => _deleteRow(r),
                              ),
                            ],
                          )),
                        ]);
                      }).toList(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(dynamic val) {
    if (val == null) return '—';
    return double.tryParse(val.toString())?.toStringAsFixed(4) ?? val.toString();
  }
}

class _BomRowDialog extends StatefulWidget {
  final String usageSkuCode;
  final Map<String, dynamic>? existing;
  const _BomRowDialog({required this.usageSkuCode, this.existing});

  @override
  State<_BomRowDialog> createState() => _BomRowDialogState();
}

class _BomRowDialogState extends State<_BomRowDialog> {
  late final TextEditingController _rawProduct;
  late final TextEditingController _rawSku;
  late final TextEditingController _cost;
  late final TextEditingController _uom;
  late final TextEditingController _unitQty;
  late final TextEditingController _bomQty;
  late final TextEditingController _bomCost;
  late final TextEditingController _bomQtyUnit;
  late final TextEditingController _sortSeq;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _rawProduct = TextEditingController(text: e?['raw_product'] ?? '');
    _rawSku = TextEditingController(text: e?['raw_product_sku_code'] ?? '');
    _cost = TextEditingController(text: e?['cost']?.toString() ?? '');
    _uom = TextEditingController(text: e?['uom'] ?? '');
    _unitQty = TextEditingController(text: e?['unit_qty_in_uom']?.toString() ?? '');
    _bomQty = TextEditingController(text: e?['bom_qty_in_uom']?.toString() ?? '');
    _bomCost = TextEditingController(text: e?['bom_cost']?.toString() ?? '');
    _bomQtyUnit = TextEditingController(text: e?['bom_qty_in_unit']?.toString() ?? '');
    _sortSeq = TextEditingController(text: e?['raw_product_sort_seq']?.toString() ?? '');
  }

  @override
  void dispose() {
    for (final c in [_rawProduct, _rawSku, _cost, _uom, _unitQty, _bomQty, _bomCost, _bomQtyUnit, _sortSeq]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    return AlertDialog(
      title: Text(isNew ? 'Add BOM Row' : 'Edit BOM Row'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field('Raw Product *', _rawProduct),
              _field('Raw Product SKU', _rawSku),
              _field('Cost', _cost, numeric: true),
              _field('UOM', _uom),
              _field('Unit Qty in UOM', _unitQty, numeric: true),
              _field('BOM Qty in UOM', _bomQty, numeric: true),
              _field('BOM Cost', _bomCost, numeric: true),
              _field('BOM Qty in Unit', _bomQtyUnit, numeric: true),
              _field('Sort Seq', _sortSeq, numeric: true),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _rawProduct.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, {
                    'usage_sku_code': widget.usageSkuCode,
                    'raw_product': _rawProduct.text.trim(),
                    if (_rawSku.text.isNotEmpty) 'raw_product_sku_code': _rawSku.text.trim(),
                    if (_cost.text.isNotEmpty) 'cost': double.tryParse(_cost.text),
                    if (_uom.text.isNotEmpty) 'uom': _uom.text.trim(),
                    if (_unitQty.text.isNotEmpty) 'unit_qty_in_uom': double.tryParse(_unitQty.text),
                    if (_bomQty.text.isNotEmpty) 'bom_qty_in_uom': double.tryParse(_bomQty.text),
                    if (_bomCost.text.isNotEmpty) 'bom_cost': double.tryParse(_bomCost.text),
                    if (_bomQtyUnit.text.isNotEmpty) 'bom_qty_in_unit': double.tryParse(_bomQtyUnit.text),
                    if (_sortSeq.text.isNotEmpty) 'raw_product_sort_seq': int.tryParse(_sortSeq.text),
                  }),
          child: Text(isNew ? 'Add' : 'Save'),
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
