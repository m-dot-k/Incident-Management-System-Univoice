import '../models/user.dart';
import 'api.dart';

// Вход по логину и паролю. При успехе возвращает пользователя и запоминает токен.
Future<({User? user, String error})> signIn(String login, String password) async {
  final r = await Api.post('/auth/login', {'login': login, 'password': password});
  if (r.ok && r.data is Map && r.data['user'] is Map && r.data['access_token'] is String) {
    try {
      final user = User.fromJson(Map<String, dynamic>.from(r.data['user']));
      Api.token = r.data['access_token'] as String;
      return (user: user, error: '');
    } catch (_) {}
  }
  return (
    user: null,
    error: r.ok ? 'Ошибка. Не удалось войти, попробуйте ещё раз' : r.error('Не удалось войти'),
  );
}
