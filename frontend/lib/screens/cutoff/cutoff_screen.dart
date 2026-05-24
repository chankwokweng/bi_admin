import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../widgets/error_banner.dart';

class CutoffScreen extends StatefulWidget {
  const CutoffScreen({super.key});

  @override
  State<CutoffScreen> createState() => _CutoffScreenState();
}

class _CutoffScreenState extends State<CutoffScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await ApiService.get('/cutoff');
      setState(() => _rows = List<Map<String, dynamic>>.from(data));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CutoffEditDialog(row: row),
    );
    if (result == null) return;
    try {
      await ApiService.put('/cutoff/${row['type']}', result);
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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('Cutoff Periods', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Spacer(),
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
                  columns: const [
                    DataColumn(label: Text('Type')),
                    DataColumn(label: Text('Last Processed Date')),
                    DataColumn(label: Text('Cutoff Date')),
                    DataColumn(label: Text('Dry Run')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: _rows.map((r) {
                    return DataRow(cells: [
                      DataCell(Text(r['type'] ?? '')),
                      DataCell(Text(_fmtDate(r['last_processed_date']))),
                      DataCell(Text(_fmtDate(r['cutoff_date']))),
                      DataCell(
                        Icon(
                          r['flag_dryrun'] == 1 ? Icons.check_box : Icons.check_box_outline_blank,
                          size: 20,
                        ),
                      ),
                      DataCell(
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          tooltip: 'Edit',
                          onPressed: () => _edit(r),
                        ),
                      ),
                    ]);
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _fmtDate(dynamic val) {
    if (val == null) return '—';
    try {
      return DateFormat('yyyy-MM-dd').format(DateTime.parse(val.toString()));
    } catch (_) {
      return val.toString();
    }
  }
}

class _CutoffEditDialog extends StatefulWidget {
  final Map<String, dynamic> row;
  const _CutoffEditDialog({required this.row});

  @override
  State<_CutoffEditDialog> createState() => _CutoffEditDialogState();
}

class _CutoffEditDialogState extends State<_CutoffEditDialog> {
  late DateTime? _lastProcessed;
  late DateTime? _cutoff;
  late bool _dryRun;
  @override
  void initState() {
    super.initState();
    _lastProcessed = _parseDate(widget.row['last_processed_date']);
    _cutoff = _parseDate(widget.row['cutoff_date']);
    _dryRun = widget.row['flag_dryrun'] == 1;
  }

  DateTime? _parseDate(dynamic val) {
    if (val == null) return null;
    try { return DateTime.parse(val.toString()); } catch (_) { return null; }
  }

  Future<void> _pickDate(bool isLastProcessed) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isLastProcessed ? _lastProcessed : _cutoff) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isLastProcessed) {
        _lastProcessed = picked;
      } else {
        _cutoff = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit — ${widget.row['type']}'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DateRow(
              label: 'Last Processed Date',
              date: _lastProcessed,
              onTap: () => _pickDate(true),
            ),
            const SizedBox(height: 12),
            _DateRow(
              label: 'Cutoff Date',
              date: _cutoff,
              onTap: () => _pickDate(false),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Dry Run'),
              value: _dryRun,
              onChanged: (v) => setState(() => _dryRun = v),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
                  Navigator.pop(context, {
                    if (_lastProcessed != null)
                      'last_processed_date': DateFormat('yyyy-MM-dd').format(_lastProcessed!),
                    if (_cutoff != null)
                      'cutoff_date': DateFormat('yyyy-MM-dd').format(_cutoff!),
                    'flag_dryrun': _dryRun ? 1 : 0,
                  });
                },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _DateRow extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  const _DateRow({required this.label, required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        TextButton(
          onPressed: onTap,
          child: Text(date != null ? DateFormat('yyyy-MM-dd').format(date!) : 'Not set'),
        ),
      ],
    );
  }
}
