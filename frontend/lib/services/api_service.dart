import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}

class ApiService {
  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  static String? _token;
  static String? _role;
  static bool _mustChangePassword = false;
  static DateTime? _lastActivity;
  static Timer? _refreshTimer;

  static const Duration _sessionTimeout = Duration(minutes: 15);
  static const Duration _refreshInterval = Duration(minutes: 13);

  static String? get token => _token;
  static String? get role => _role;
  static bool get mustChangePassword => _mustChangePassword;
  static bool get isLoggedIn => _token != null;
  static bool get isSuperAdmin => _role == 'super_admin';

  static void recordActivity() {
    _lastActivity = DateTime.now();
  }

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    _role = prefs.getString('role');
    _mustChangePassword = prefs.getBool('must_change_password') ?? false;
    if (_token != null) _startRefreshTimer();
  }

  static void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) async {
      if (_lastActivity == null) return;
      final idle = DateTime.now().difference(_lastActivity!);
      if (idle < _sessionTimeout) {
        try {
          await refresh();
        } catch (_) {
          await logout();
        }
      } else {
        await logout();
      }
    });
  }

  static Future<void> saveSession(String token, String role, bool mustChange) async {
    _token = token;
    _role = role;
    _mustChangePassword = mustChange;
    _lastActivity = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await prefs.setString('role', role);
    await prefs.setBool('must_change_password', mustChange);
    _startRefreshTimer();
  }

  static Future<void> logout() async {
    _token = null;
    _role = null;
    _mustChangePassword = false;
    _lastActivity = null;
    _refreshTimer?.cancel();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('role');
    await prefs.remove('must_change_password');
  }

  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  static Future<dynamic> get(String path, {Map<String, String>? params}) async {
    recordActivity();
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: params);
    final res = await http.get(uri, headers: _headers);
    return _handle(res);
  }

  static Future<dynamic> post(String path, [dynamic body]) async {
    recordActivity();
    final res = await http.post(
      Uri.parse('$_baseUrl$path'),
      headers: _headers,
      body: body != null ? jsonEncode(body) : null,
    );
    return _handle(res);
  }

  static Future<dynamic> put(String path, dynamic body) async {
    recordActivity();
    final res = await http.put(
      Uri.parse('$_baseUrl$path'),
      headers: _headers,
      body: jsonEncode(body),
    );
    return _handle(res);
  }

  static Future<dynamic> delete(String path, {Map<String, String>? params}) async {
    recordActivity();
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: params);
    final res = await http.delete(uri, headers: _headers);
    return _handle(res);
  }

  static Future<http.Response> getRaw(String path, {Map<String, String>? params}) async {
    recordActivity();
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: params);
    return http.get(uri, headers: _headers);
  }

  static Future<void> refresh() async {
    final res = await http.post(Uri.parse('$_baseUrl/auth/refresh'), headers: _headers);
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      await saveSession(data['access_token'], data['role'], data['must_change_password']);
    } else {
      throw ApiException(res.statusCode, 'Session expired');
    }
  }

  static dynamic _handle(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return null;
      return jsonDecode(res.body);
    }
    String message = 'Request failed';
    try {
      final body = jsonDecode(res.body);
      message = body['detail'] ?? message;
    } catch (_) {}
    throw ApiException(res.statusCode, message);
  }
}
