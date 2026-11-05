import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;

mixin SafeState<T extends StatefulWidget> on State<T> {
  void safeSetState(VoidCallback fn) {
    if (mounted) setState(fn);
  }
}

// Текст ошибки выбора фото: отдельно — когда нет доступа к камере или галерее
String pickErrorText(Object e) {
  if (e is PlatformException && (e.code.contains('denied') || e.code.contains('access'))) {
    return 'Нет доступа к камере или фото. Разрешите его в настройках iPhone для этого приложения.';
  }
  if (e is PlatformException && e.code.contains('camera')) return 'Камера недоступна на этом устройстве';
  return 'Ошибка. Не удалось получить фото';
}

void snack(BuildContext c, String text, {Color? color, int ms = 2500}) {
  ScaffoldMessenger.of(c)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(text), backgroundColor: color, duration: Duration(milliseconds: ms)));
}
