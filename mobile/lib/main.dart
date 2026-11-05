import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'theme.dart';

void main() {
  // В релизе сбой при отрисовке блока показывается как спокойное «Ошибка», а не серый экран.
  // В debug остаётся стандартный красный экран, чтобы ошибки было видно при разработке.
  if (kReleaseMode) {
    ErrorWidget.builder = (details) {
      debugPrint('UI error: ${details.exceptionAsString()}');
      return Container(
        color: kBg,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: const Text(
          'Ошибка. Не удалось показать этот блок',
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          style: TextStyle(color: kMuted, fontSize: 14),
        ),
      );
    };
  }
  runApp(const UNIvoiceApp());
}
