import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'services/api_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/change_password_screen.dart';
import 'screens/sftp/sftp_screen.dart';
import 'screens/cutoff/cutoff_screen.dart';
import 'screens/products/products_screen.dart';
import 'screens/bom/bom_screen.dart';
import 'screens/admin/users_screen.dart';
import 'widgets/app_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService.init();
  runApp(const BiAdminApp());
}

final _router = GoRouter(
  initialLocation: '/sftp',
  redirect: (context, state) {
    final loggedIn = ApiService.isLoggedIn;
    final onAuth = state.uri.path == '/login' || state.uri.path == '/change-password';
    if (!loggedIn && !onAuth) return '/login';
    if (loggedIn && ApiService.mustChangePassword && state.uri.path != '/change-password') {
      return '/change-password';
    }
    if (loggedIn && state.uri.path == '/login') return '/sftp';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
    GoRoute(path: '/change-password', builder: (_, _) => const ChangePasswordScreen()),
    ShellRoute(
      builder: (_, state, child) => AppShell(child: child),
      routes: [
        GoRoute(path: '/sftp', builder: (_, _) => const SftpScreen()),
        GoRoute(path: '/cutoff', builder: (_, _) => const CutoffScreen()),
        GoRoute(path: '/products', builder: (_, _) => const ProductsScreen()),
        GoRoute(path: '/bom', builder: (_, _) => const BomScreen()),
        GoRoute(path: '/admin/users', builder: (_, _) => const UsersScreen()),
      ],
    ),
  ],
);

class BiAdminApp extends StatelessWidget {
  const BiAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'BI Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1A237E),
        useMaterial3: true,
      ),
      routerConfig: _router,
    );
  }
}
