import 'package:flutter/material.dart';

import 'screens/auth_choice_screen.dart';
import 'theme.dart';
import 'widgets/keyboard_dismiss.dart';

class UNIvoiceApp extends StatelessWidget {
  const UNIvoiceApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'UNIvoice',
        theme: buildTheme(),
        builder: (context, child) => KeyboardDismiss(child: child ?? const SizedBox.shrink()),
        home: const AuthChoiceScreen(),
      );
}
