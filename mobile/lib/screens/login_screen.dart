import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../utils/ui.dart';
import '../widgets/status_text.dart';
import 'home_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SafeState<LoginScreen> {
  final _loginC = TextEditingController();
  final _passC = TextEditingController();
  String _msg = '';
  bool _loading = false;

  @override
  void dispose() {
    _loginC.dispose();
    _passC.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_loginC.text.trim().isEmpty || _passC.text.isEmpty) {
      setState(() => _msg = 'Введите логин и пароль');
      return;
    }
    // Сервер всё равно отклонит такие данные — не тратим запрос
    if (_loginC.text.trim().length < 3 || _passC.text.length < 8) {
      setState(() => _msg = 'Неверный логин или пароль');
      return;
    }
    setState(() {
      _loading = true;
      _msg = '';
    });

    final res = await signIn(_loginC.text.trim(), _passC.text);
    if (!mounted) return;
    final user = res.user;
    if (user != null) {
      openHome(context, user);
      return;
    }
    setState(() {
      _loading = false;
      _msg = res.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Вход в систему')),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _loginC,
              decoration: const InputDecoration(labelText: 'Логин', prefixIcon: Icon(Icons.person)),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passC,
              decoration: const InputDecoration(labelText: 'Пароль', prefixIcon: Icon(Icons.lock)),
              obscureText: true,
              onSubmitted: (_) => _loading ? null : _login(),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loading ? null : _login,
              icon: const Icon(Icons.login),
              label: const Text('Войти'),
            ),
            const SizedBox(height: 20),
            StatusText(_msg),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () =>
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
              child: const Text('Нет аккаунта? Зарегистрироваться'),
            ),
          ],
        ),
      ),
    );
  }
}
