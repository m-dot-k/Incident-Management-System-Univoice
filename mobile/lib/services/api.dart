import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config.dart';

class ApiResult {
  final int status; // 0 = нет связи / таймаут
  final dynamic data;
  ApiResult(this.status, this.data);

  bool get ok => status >= 200 && status < 300;
  static final _cyr = RegExp(r'[А-Яа-яЁё]');
  static const _fields = {
    'login': 'Логин',
    'password': 'Пароль',
    'email': 'Email',
    'display_name': 'Имя',
    'title': 'Заголовок',
    'description': 'Описание',
    'category': 'Категория',
    'reason': 'Причина',
    'type': 'Тип обращения',
    'comment': 'Комментарий',
  };

  /// Короткое понятное сообщение вместо кодов ответа и технического текста
  String error([String fallback = 'Ошибка. Попробуйте ещё раз']) {
    final detail = data is Map ? data['detail'] : null;
    if (status == 0) {
      return detail is String && detail.isNotEmpty ? detail : 'Нет связи с сервером. Проверьте интернет';
    }
    if (status >= 500) return 'Ошибка сервера. Попробуйте позже';
    // Русские сообщения сервера («Неверный логин или пароль» и т.п.) показываем как есть
    if (detail is String && _cyr.hasMatch(detail)) return detail.trim();
    // Ошибки проверки полей (422) превращаем в «Поле: что не так»
    if (detail is List && detail.isNotEmpty && detail.first is Map) {
      final e = detail.first as Map;
      final loc = e['loc'];
      final name = loc is List && loc.isNotEmpty ? _fields['${loc.last}'] : null;
      final type = '${e['type']}';
      final what = type.contains('too_short')
          ? 'слишком мало символов'
          : type.contains('too_long')
              ? 'слишком много символов'
              : type.contains('pattern')
                  ? 'недопустимые символы'
                  : type == 'missing'
                      ? 'обязательное поле'
                      : 'неверное значение';
      return name == null ? 'Проверьте введённые данные' : '$name: $what';
    }
    return switch (status) {
      401 => 'Нужно войти в аккаунт',
      403 => 'Недостаточно прав для этого действия',
      404 => 'Не найдено',
      408 => 'Сервер долго не отвечает. Попробуйте ещё раз',
      409 => 'Такая запись уже существует',
      413 => 'Файл слишком большой',
      422 => 'Проверьте введённые данные',
      429 => 'Слишком много попыток. Подождите немного',
      _ => fallback,
    };
  }
}

class Api {
  // В памяти. Для сохранения между запусками — flutter_secure_storage.
  static String? token;

  static Future<ApiResult> get(String path) => _send('GET', path);
  static Future<ApiResult> post(String path, Map<String, dynamic> body) => _send('POST', path, body);
  static Future<ApiResult> delete(String path, [Map<String, dynamic>? body]) => _send('DELETE', path, body);
  static Future<ApiResult> patch(String path, Map<String, dynamic> body) => _send('PATCH', path, body);

  // MultipartFile.fromPath не определяет тип файла и шлёт application/octet-stream,
  // а сервер принимает только image/jpeg и image/png. Определяем тип по первым байтам.
  static Future<MediaType?> _imageType(File f) async {
    final b = await f.openRead(0, 8).expand((c) => c).toList();
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return MediaType('image', 'jpeg');
    if (b.length >= 4 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return MediaType('image', 'png');
    return null;
  }

  // Загрузка фото: POST multipart/form-data, поле файла называется 'file'
  static Future<ApiResult> uploadImage(String path, Map<String, String> fields, File file, {String field = 'file'}) async {
    try {
      final type = await _imageType(file);
      if (type == null) return ApiResult(0, {'detail': 'Нужно фото в формате JPEG или PNG'});
      final req = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'))
        ..fields.addAll(fields)
        ..files.add(await http.MultipartFile.fromPath(field, file.path,
            contentType: type, filename: type.subtype == 'png' ? 'photo.png' : 'photo.jpg'));
      if (token != null) req.headers['Authorization'] = 'Bearer $token';
      final r = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 30)));
      dynamic data;
      try {
        data = r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
      } catch (_) {}
      return ApiResult(r.statusCode, data);
    } on TimeoutException {
      return ApiResult(0, {'detail': 'Сервер не отвечает. Попробуйте ещё раз'});
    } catch (_) {
      return ApiResult(0, {'detail': 'Нет связи с сервером. Проверьте интернет'});
    }
  }

  static Future<ApiResult> _send(String method, String path, [Map<String, dynamic>? body]) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    final Future<http.Response> req = switch (method) {
      'GET' => http.get(uri, headers: headers),
      'POST' => http.post(uri, headers: headers, body: jsonEncode(body)),
      'PATCH' => http.patch(uri, headers: headers, body: jsonEncode(body)),
      _ => http.delete(uri, headers: headers, body: body == null ? null : jsonEncode(body)),
    };
    try {
      final r = await req.timeout(const Duration(seconds: 10));
      dynamic data;
      try {
        data = r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
      } catch (_) {} // не-JSON ответ (например, HTML ошибки 500)
      return ApiResult(r.statusCode, data);
    } on TimeoutException {
      return ApiResult(0, {'detail': 'Сервер не отвечает. Попробуйте ещё раз'});
    } catch (_) {
      return ApiResult(0, {'detail': 'Нет связи с сервером. Проверьте интернет'});
    }
  }
}
