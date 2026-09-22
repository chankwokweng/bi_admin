import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../widgets/error_banner.dart';

// Known bi-app pipeline stage markers (see run-app.sh's `log "Running ...X"`
// calls) - offered as a convenience dropdown, but the backend filter itself
// just does a substring match, so this list doesn't need to stay perfectly
// in sync with the script to keep working.
const _kStages = [
  '1_extract_collection_XLS_to_DB',
  '1a_process_invoice_data_using_webscrape',
  '2_extract_service_XLS_to_DB',
  '2a_usage_BOM',
  '3_extract_commission_HTML_to_DB',
  '4_extract_customer_XLS_to_DB',
  '9_transform',
  '7_Monthly_Actuals_with_SM_commission',
  '8_New_Commission',
];

const _kLevels = ['INFO', 'WARNING', 'ERROR', 'CRITICAL', 'DEBUG'];

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  DateTime _dateFrom = DateTime.now();
  DateTime _dateTo = DateTime.now();
  String? _level;
  String? _stage;
  final _searchCtrl = TextEditingController();

  static const _pageSize = 100;
  int _offset = 0;
  int _total = 0;
  List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _fmt(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _dateFrom : _dateTo,
      firstDate: DateTime(2025, 1, 1),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _dateFrom = picked;
      } else {
        _dateTo = picked;
      }
    });
  }

  Future<void> _load({bool resetOffset = true}) async {
    setState(() {
      _loading = true;
      _error = null;
      if (resetOffset) _offset = 0;
    });
    try {
      final params = <String, String>{
        'date_from': _fmt(_dateFrom),
        'date_to': _fmt(_dateTo),
        'limit': '$_pageSize',
        'offset': '$_offset',
      };
      if (_level != null) params['level'] = _level!;
      if (_stage != null) params['stage'] = _stage!;
      if (_searchCtrl.text.trim().isNotEmpty) params['q'] = _searchCtrl.text.trim();

      final data = await ApiService.get('/logs/entries', params: params);
      setState(() {
        _total = data['total'] as int;
        _items = List<Map<String, dynamic>>.from(data['items']);
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _nextPage() {
    if (_offset + _pageSize >= _total) return;
    setState(() => _offset += _pageSize);
    _load(resetOffset: false);
  }

  void _prevPage() {
    if (_offset == 0) return;
    setState(() => _offset = (_offset - _pageSize).clamp(0, 1 << 30));
    _load(resetOffset: false);
  }

  Color _levelColor(String? level) {
    switch (level) {
      case 'ERROR':
      case 'CRITICAL':
        return Colors.red;
      case 'WARNING':
        return Colors.orange[800]!;
      case 'INFO':
        return Colors.blue[700]!;
      case 'DEBUG':
        return Colors.grey[600]!;
      default:
        return Colors.grey[500]!;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFilterBar(),
          const SizedBox(height: 12),
          if (_error != null) ErrorBanner(message: _error!),
          Expanded(child: _buildResults()),
          _buildPagination(),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _DateChip(label: 'From', date: _dateFrom, onTap: () => _pickDate(true)),
        _DateChip(label: 'To', date: _dateTo, onTap: () => _pickDate(false)),
        SizedBox(
          width: 140,
          child: DropdownButtonFormField<String?>(
            initialValue: _level,
            decoration: const InputDecoration(labelText: 'Level', isDense: true),
            items: [
              const DropdownMenuItem(value: null, child: Text('All')),
              ..._kLevels.map((l) => DropdownMenuItem(value: l, child: Text(l))),
            ],
            onChanged: (v) => setState(() => _level = v),
          ),
        ),
        SizedBox(
          width: 260,
          child: DropdownButtonFormField<String?>(
            initialValue: _stage,
            decoration: const InputDecoration(labelText: 'Stage', isDense: true),
            items: [
              const DropdownMenuItem(value: null, child: Text('All')),
              ..._kStages.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))),
            ],
            onChanged: (v) => setState(() => _stage = v),
          ),
        ),
        SizedBox(
          width: 240,
          child: TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              labelText: 'Search message',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
            onSubmitted: (_) => _load(),
          ),
        ),
        FilledButton.icon(
          icon: _loading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.filter_alt),
          label: const Text('Apply'),
          onPressed: _loading ? null : () => _load(),
        ),
      ],
    );
  }

  Widget _buildResults() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      return const Center(child: Text('No log entries match these filters'));
    }
    return ListView.separated(
      itemCount: _items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final e = _items[i];
        final level = e['level'] as String?;
        final ts = e['timestamp'] as String?;
        final stage = e['stage'] as String?;
        final message = e['message'] as String;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 150,
                child: Text(
                  ts ?? '',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.black54),
                ),
              ),
              SizedBox(
                width: 70,
                child: level == null
                    ? const SizedBox.shrink()
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _levelColor(level).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          level,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _levelColor(level)),
                        ),
                      ),
              ),
              SizedBox(
                width: 180,
                child: Text(
                  stage ?? '',
                  style: const TextStyle(fontSize: 12, color: Colors.black45),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                child: SelectableText(
                  message,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPagination() {
    if (_total == 0) return const SizedBox.shrink();
    final start = _offset + 1;
    final end = (_offset + _items.length).clamp(0, _total);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text('$start-$end of $_total', style: TextStyle(color: Colors.grey[700])),
          const SizedBox(width: 12),
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: _offset == 0 ? null : _prevPage),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: _offset + _pageSize >= _total ? null : _nextPage),
        ],
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  final String label;
  final DateTime date;
  final VoidCallback onTap;
  const _DateChip({required this.label, required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[400]!),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_today, size: 16),
            const SizedBox(width: 6),
            Text('$label: ${DateFormat('yyyy-MM-dd').format(date)}'),
          ],
        ),
      ),
    );
  }
}
