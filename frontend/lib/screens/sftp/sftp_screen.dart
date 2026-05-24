import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../widgets/error_banner.dart';

class SftpScreen extends StatefulWidget {
  const SftpScreen({super.key});

  @override
  State<SftpScreen> createState() => _SftpScreenState();
}

class _SftpScreenState extends State<SftpScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  static const _roots = ['data', 'logs', 'output'];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _roots.length, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabs,
            tabs: _roots.map((r) => Tab(text: r.toUpperCase())).toList(),
            labelColor: const Color(0xFF1A237E),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: _roots.map((r) => _FileBrowser(root: r)).toList(),
          ),
        ),
      ],
    );
  }
}

class _FileBrowser extends StatefulWidget {
  final String root;
  const _FileBrowser({required this.root});

  @override
  State<_FileBrowser> createState() => _FileBrowserState();
}

class _FileBrowserState extends State<_FileBrowser> {
  final List<String> _breadcrumb = [];
  List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  String? _error;
  bool _uploading = false;

  String get _subpath => _breadcrumb.join('/');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await ApiService.get('/sftp/list', params: {
        'root': widget.root,
        'subpath': _subpath,
      });
      setState(() => _items = List<Map<String, dynamic>>.from(data));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _enter(String dir) {
    setState(() => _breadcrumb.add(dir));
    _load();
  }

  void _up() {
    if (_breadcrumb.isNotEmpty) {
      setState(() => _breadcrumb.removeLast());
      _load();
    }
  }

  Future<void> _download(String name) async {
    final path = _breadcrumb.isEmpty ? name : '$_subpath/$name';
    final res = await ApiService.getRaw('/sftp/download', params: {
      'root': widget.root,
      'subpath': path,
    });
    if (res.statusCode == 200) {
      webDownload(name, res.bodyBytes);
    } else {
      if (mounted) _showError('Download failed');
    }
  }

  Future<void> _delete(String name) async {
    final confirmed = await _confirm('Delete "$name"? This cannot be undone.');
    if (!confirmed) return;
    final path = _breadcrumb.isEmpty ? name : '$_subpath/$name';
    try {
      await ApiService.delete('/sftp/delete', params: {
        'root': widget.root,
        'subpath': path,
      });
      _load();
    } catch (e) {
      if (mounted) _showError(e.toString());
    }
  }

  Future<void> _archiveFile(String name) async {
    final confirmed = await _confirm('Archive "$name"? It will be zipped and moved to _archive/.');
    if (!confirmed) return;
    final path = _breadcrumb.isEmpty ? name : '$_subpath/$name';
    try {
      await ApiService.post(
        '/sftp/archive?root=${widget.root}&subpath=${Uri.encodeComponent(path)}',
        null,
      );
      _load();
    } catch (e) {
      if (mounted) _showError(e.toString());
    }
  }

  Future<bool> _confirm(String msg) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Confirm'),
            content: Text(msg),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
            ],
          ),
        ) ??
        false;
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  Future<void> _uploadFile() async {
    setState(() => _uploading = true);
    try {
      await webUpload(widget.root, _subpath, _load);
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isData = widget.root == 'data';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (_breadcrumb.isNotEmpty)
                IconButton(icon: const Icon(Icons.arrow_back), onPressed: _up, tooltip: 'Up'),
              Expanded(
                child: Wrap(
                  children: [
                    InkWell(
                      onTap: () { _breadcrumb.clear(); _load(); },
                      child: Text(widget.root, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    for (int i = 0; i < _breadcrumb.length; i++) ...[
                      const Text(' / '),
                      InkWell(
                        onTap: () {
                          setState(() => _breadcrumb.removeRange(i + 1, _breadcrumb.length));
                          _load();
                        },
                        child: Text(_breadcrumb[i]),
                      ),
                    ],
                  ],
                ),
              ),
              if (isData)
                FilledButton.icon(
                  icon: _uploading
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.upload_file),
                  label: const Text('Upload'),
                  onPressed: _uploading ? null : _uploadFile,
                ),
              const SizedBox(width: 8),
              IconButton(icon: const Icon(Icons.refresh), onPressed: _load, tooltip: 'Refresh'),
            ],
          ),
          const SizedBox(height: 8),
          if (_error != null) ErrorBanner(message: _error!),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: _items.isEmpty
                  ? const Center(child: Text('Empty directory'))
                  : ListView.separated(
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final item = _items[i];
                        final isDir = item['is_dir'] as bool;
                        final name = item['name'] as String;
                        final size = item['size'] as int;
                        final modified = item['modified'] as String;

                        return ListTile(
                          leading: Icon(
                            isDir ? Icons.folder : Icons.insert_drive_file,
                            color: isDir ? Colors.amber[700] : Colors.blueGrey,
                          ),
                          title: Text(name),
                          subtitle: isDir
                              ? null
                              : Text(_formatSize(size), style: const TextStyle(fontSize: 12)),
                          trailing: isDir
                              ? null
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (modified.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 12),
                                        child: Text(
                                          _formatDate(modified),
                                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                        ),
                                      ),
                                    IconButton(
                                      icon: const Icon(Icons.download, size: 20),
                                      tooltip: 'Download',
                                      onPressed: () => _download(name),
                                    ),
                                    if (!isData && name != '_archive')
                                      IconButton(
                                        icon: const Icon(Icons.archive, size: 20),
                                        tooltip: 'Archive (zip)',
                                        onPressed: () => _archiveFile(name),
                                      ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                                      tooltip: 'Delete',
                                      onPressed: () => _delete(name),
                                    ),
                                  ],
                                ),
                          onTap: isDir ? () => _enter(name) : null,
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  String _formatDate(String iso) {
    try {
      return DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
  }
}

// Stubs implemented in sftp_web.dart (conditional import)
void webDownload(String filename, List<int> bytes) {}
Future<void> webUpload(String root, String subpath, VoidCallback onDone) async {}
