import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/api_status_icon.dart';
import '../widgets/fade_in.dart';
import '../widgets/home_scope.dart';
import 'auth_choice_screen.dart';

class ProfileTab extends StatelessWidget {
  final User user;
  const ProfileTab({super.key, required this.user});

  String get _role => switch (user.role) {
        'admin' => 'Администратор',
        'employee' => 'Сотрудник',
        _ => 'Студент',
      };

  Widget _info(IconData icon, String label, String value) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(16), border: Border.all(color: kBorder)),
        child: ListTile(
          leading: Icon(icon, color: kAccent),
          title: Text(label, style: const TextStyle(fontSize: 12, color: kMuted)),
          subtitle: Text(value, style: const TextStyle(fontSize: 16, color: kText)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final initial = user.displayName.isEmpty ? '?' : user.displayName[0].toUpperCase();
    return Scaffold(
      appBar: AppBar(leading: HomeScope.backButton(context), title: const Text('Профиль'), actions: const [ApiStatusIcon()]),
      body: FadeIn(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: CircleAvatar(
                radius: 40,
                backgroundColor: const Color(0xFF3B31B0),
                child: Text(initial, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 14),
            Center(child: Text(user.displayName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
            const SizedBox(height: 24),
            _info(Icons.badge_outlined, 'Роль', _role),
            _info(Icons.mail_outline, 'Email', user.email),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(16), foregroundColor: const Color(0xFFFF7A8A)),
              icon: const Icon(Icons.logout),
              label: const Text('Выйти'),
              onPressed: () {
                Api.post('/auth/logout', {}); // ответ не важен: токен забываем в любом случае
                Api.token = null;
                Navigator.pushAndRemoveUntil(
                    context, MaterialPageRoute(builder: (_) => const AuthChoiceScreen()), (_) => false);
              },
            ),
          ],
        ),
      ),
    );
  }
}
