import 'package:flutter_test/flutter_test.dart';
import 'package:univoice/services/api.dart';
import 'package:univoice/utils/format.dart';
import 'package:univoice/utils/validators.dart';

void main() {
  group('ApiResult.error', () {
    test('shows Russian server messages as is', () {
      expect(ApiResult(401, {'detail': 'Неверный логин или пароль'}).error(), 'Неверный логин или пароль');
    });

    test('turns status codes into plain words', () {
      expect(ApiResult(401, {'detail': 'Not authenticated'}).error(), 'Нужно войти в аккаунт');
      expect(ApiResult(403, null).error(), 'Недостаточно прав для этого действия');
      expect(ApiResult(500, null).error(), 'Ошибка сервера. Попробуйте позже');
    });

    test('explains field validation errors', () {
      final r = ApiResult(422, {
        'detail': [
          {
            'loc': ['body', 'title'],
            'type': 'string_too_short'
          }
        ]
      });
      expect(r.error(), 'Заголовок: слишком мало символов');
    });

    test('uses the connection message when there is no response', () {
      expect(ApiResult(0, null).error(), 'Нет связи с сервером. Проверьте интернет');
    });
  });

  test('fmtDate prints day.month.year hours:minutes', () {
    expect(fmtDate(null), '—');
    expect(fmtDate(DateTime(2026, 3, 7, 9, 5)), '07.03.2026 09:05');
  });

  test('login rule matches the server', () {
    expect(loginRe.hasMatch('student_1'), isTrue);
    expect(loginRe.hasMatch('ab'), isFalse);
    expect(loginRe.hasMatch('студент'), isFalse);
  });
}
