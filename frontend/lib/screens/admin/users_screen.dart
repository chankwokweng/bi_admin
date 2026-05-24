import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../widgets/error_banner.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<Map<String, dynamic>> _users = [];
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
      final data = await ApiService.get('/users');
      setState(() => _users = List<Map<String, dynamic>>.from(data));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createUser() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _CreateUserDialog(),
    );
    if (result == null) return;
    try {
      final data = await ApiService.post('/users', result);
      if (mounted) {
        final temp = data['temp_password'] ?? '';
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('User Created'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Email: ${data['email']}'),
                const SizedBox(height: 8),
                const Text('Temporary password (share securely):'),
                const SizedBox(height: 4),
                SelectableText(temp, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                const Text('User must change password on first login.', style: TextStyle(color: Colors.orange)),
              ],
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        );
      }
      _load();
    } catch (e) {
      if (mounted) _showError(e.toString());
    }
  }

  Future<void> _resetPassword(Map<String, dynamic> user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reset Password'),
        content: Text('Reset password for ${user['email']}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reset')),
        ],
      ),
    ) ?? false;
    if (!confirmed) return;
    try {
      final data = await ApiService.post('/users/${user['id']}/reset-password');
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Password Reset'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('New temporary password:'),
                const SizedBox(height: 8),
                SelectableText(data['temp_password'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        );
      }
    } catch (e) {
      if (mounted) _showError(e.toString());
    }
  }

  Future<void> _toggleApproval(Map<String, dynamic> user) async {
    final approved = !(user['is_approved'] as bool);
    try {
      await ApiService.put('/users/${user['id']}', {'is_approved': approved});
      _load();
    } catch (e) {
      if (mounted) _showError(e.toString());
    }
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete User'),
        content: Text('Delete ${user['email']}? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    ) ?? false;
    if (!confirmed) return;
    try {
      await ApiService.delete('/users/${user['id']}');
      _load();
    } catch (e) {
      if (mounted) _showError(e.toString());
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
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
              const Text('User Management', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Spacer(),
              FilledButton.icon(
                icon: const Icon(Icons.person_add),
                label: const Text('Create User'),
                onPressed: _createUser,
              ),
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
                  columns: const [
                    DataColumn(label: Text('Email')),
                    DataColumn(label: Text('Role')),
                    DataColumn(label: Text('Approved')),
                    DataColumn(label: Text('Must Change PW')),
                    DataColumn(label: Text('Created')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: _users.map((u) {
                    return DataRow(cells: [
                      DataCell(Text(u['email'] ?? '')),
                      DataCell(Chip(
                        label: Text(u['role'] ?? ''),
                        backgroundColor: u['role'] == 'super_admin'
                            ? const Color(0xFF1A237E)
                            : Colors.grey[200],
                        labelStyle: TextStyle(
                          color: u['role'] == 'super_admin' ? Colors.white : Colors.black87,
                          fontSize: 12,
                        ),
                      )),
                      DataCell(Switch(
                        value: u['is_approved'] as bool,
                        onChanged: (_) => _toggleApproval(u),
                      )),
                      DataCell(Icon(
                        u['must_change_password'] as bool ? Icons.warning_amber : Icons.check_circle,
                        color: u['must_change_password'] as bool ? Colors.orange : Colors.green,
                        size: 20,
                      )),
                      DataCell(Text(_fmtDate(u['created_at']))),
                      DataCell(Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.lock_reset, size: 18),
                            tooltip: 'Reset Password',
                            onPressed: () => _resetPassword(u),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                            tooltip: 'Delete',
                            onPressed: () => _deleteUser(u),
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
    );
  }

  String _fmtDate(dynamic val) {
    if (val == null) return '';
    try { return val.toString().substring(0, 10); } catch (_) { return val.toString(); }
  }
}

class _CreateUserDialog extends StatefulWidget {
  const _CreateUserDialog();

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  String _role = 'user';

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create User'),
      content: SizedBox(
        width: 340,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                keyboardType: TextInputType.emailAddress,
                validator: (v) => v != null && v.contains('@') ? null : 'Enter a valid email',
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Role', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'user', child: Text('User')),
                  DropdownMenuItem(value: 'super_admin', child: Text('Super Admin')),
                ],
                onChanged: (v) => setState(() => _role = v ?? 'user'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, {'email': _emailCtrl.text.trim(), 'role': _role});
            }
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}
