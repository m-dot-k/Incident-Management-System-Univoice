import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/api_status_icon.dart';
import '../widgets/fade_in.dart';
import '../widgets/hero_art.dart';
import 'login_screen.dart';
import 'register_screen.dart';

class AuthChoiceScreen extends StatelessWidget {
  const AuthChoiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Align(alignment: Alignment.centerRight, child: ApiStatusIcon()),
              Expanded(
                child: FadeIn(
                  child: Container(
                    decoration: BoxDecoration(
                      color: kSurface,
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: kBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(110)),
                              child: CustomPaint(painter: HeroArt(), child: const SizedBox.expand()),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Ваш голос\nимеет значение',
                                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, height: 1.15, color: kText)),
                              const SizedBox(height: 10),
                              const Text(
                                'Жалобы и предложения по учёбе, оборудованию и инфраструктуре — в одном приложении.',
                                style: TextStyle(fontSize: 14, height: 1.4, color: kMuted),
                              ),
                              const SizedBox(height: 22),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 18), shape: const StadiumBorder()),
                                onPressed: () =>
                                    Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('Войти', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                    SizedBox(width: 8),
                                    Icon(Icons.arrow_forward, size: 18),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Center(
                                child: TextButton(
                                  style: TextButton.styleFrom(foregroundColor: kMuted),
                                  onPressed: () =>
                                      Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
                                  child: const Text('Создать аккаунт'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
