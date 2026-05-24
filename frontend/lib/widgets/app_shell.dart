import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_service.dart';

class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _Sidebar(currentPath: GoRouterState.of(context).uri.path),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final String currentPath;
  const _Sidebar({required this.currentPath});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: const Color(0xFF1A237E),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: const Text('BI Admin', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _NavItem(icon: Icons.folder, label: 'SFTP Files', path: '/sftp', current: currentPath),
                _NavItem(icon: Icons.calendar_today, label: 'Cutoff Periods', path: '/cutoff', current: currentPath),
                _NavItem(icon: Icons.inventory_2, label: 'Products', path: '/products', current: currentPath),
                _NavItem(icon: Icons.account_tree, label: 'BOM', path: '/bom', current: currentPath),
                if (ApiService.isSuperAdmin)
                  _NavItem(icon: Icons.manage_accounts, label: 'Users', path: '/admin/users', current: currentPath),
              ],
            ),
          ),
          const Divider(height: 1),
          _LogoutTile(),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String path;
  final String current;
  const _NavItem({required this.icon, required this.label, required this.path, required this.current});

  @override
  Widget build(BuildContext context) {
    final selected = current == path || current.startsWith('$path/');
    return ListTile(
      leading: Icon(icon, color: selected ? const Color(0xFF1A237E) : Colors.grey[700]),
      title: Text(label, style: TextStyle(
        color: selected ? const Color(0xFF1A237E) : Colors.grey[800],
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
      )),
      tileColor: selected ? const Color(0xFFE8EAF6) : null,
      onTap: () => context.go(path),
    );
  }
}

class _LogoutTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.logout, color: Colors.red),
      title: const Text('Sign Out', style: TextStyle(color: Colors.red)),
      onTap: () async {
        await ApiService.logout();
        if (context.mounted) context.go('/login');
      },
    );
  }
}
