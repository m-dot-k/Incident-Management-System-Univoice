import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/auth_service.dart';
import '../utils/ui.dart';
import '../utils/validators.dart';
import '../widgets/status_text.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> with SafeState<RegisterScreen> {
  final _loginC = TextEditingController();
  final _nameC = TextEditingController();
  final _emailC = TextEditingController();
  final _passC = TextEditingController();
  String _msg = '';
  bool _ok = false, _loading = false;

  @override
  void dispose() {
    for (final c in [_loginC, _nameC, _emailC, _passC]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _register() async {
    if (_loginC.text.trim().isEmpty ||
        _nameC.text.trim().isEmpty ||
        _emailC.text.trim().isEmpty ||
        _passC.text.isEmpty) {
      setState(() => _msg = 'Заполните все обязательные поля (*)!');
      return;
    }
    if (!loginRe.hasMatch(_loginC.text.trim())) {
      setState(() => _msg = 'Логин: 3–30 символов, только латиница, цифры и _ . -');
      return;
    }
    if (!emailRe.hasMatch(_emailC.text.trim())) {
      setState(() => _msg = 'Некорректный email');
      return;
    }
    if (_passC.text.length < 8) {
      setState(() => _msg = 'Пароль должен быть не менее 8 символов!');
      return;
    }
    setState(() {
      _loading = true;
      _ok = false;
      _msg = '';
    });

    final r = await Api.post('/auth/register', {
      'login': _loginC.text.trim(),
      'display_name': _nameC.text.trim(),
      'email': _emailC.text.trim(),
      'password': _passC.text,
    });
    if (!mounted) return;

    if (r.status == 201) {
      setState(() {
        _ok = true;
        _msg = 'Регистрация успешна! Входим…';
      });
      // Сразу входим, чтобы не вводить те же данные второй раз
      final res = await signIn(_loginC.text.trim(), _passC.text);
      if (!mounted) return;
      final user = res.user;
      if (user != null) {
        openHome(context, user);
      } else {
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) Navigator.pop(context);
      }
    } else {
      setState(() {
        _loading = false;
        _msg = 'Ошибка: ${r.error('Не удалось зарегистрироваться')}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Регистрация студента')),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
                controller: _loginC,
                decoration: const InputDecoration(labelText: 'Логин *', prefixIcon: Icon(Icons.account_circle))),
            const SizedBox(height: 12),
            TextField(
                controller: _nameC,
                decoration: const InputDecoration(labelText: 'ФИО / Отображаемое имя *', prefixIcon: Icon(Icons.badge))),
            const SizedBox(height: 12),
            TextField(
              controller: _emailC,
              decoration: const InputDecoration(labelText: 'Email *', prefixIcon: Icon(Icons.email)),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passC,
              decoration: const InputDecoration(
                  labelText: 'Пароль * (мин. 8 символов)', prefixIcon: Icon(Icons.lock_outline)),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loading ? null : _register,
              icon: const Icon(Icons.app_registration),
              label: const Text('Зарегистрироваться'),
            ),
            const SizedBox(height: 16),
            StatusText(_msg, ok: _ok),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () =>
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
              child: const Text('Уже есть аккаунт? Войти'),
            ),
          ],
        ),
      ),
    );
  }
}
