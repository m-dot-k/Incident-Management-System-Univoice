import 'dart:io';

// Адрес задаётся при сборке: flutter run --dart-define=API_URL=https://api.example.com
const String _apiUrl = String.fromEnvironment('API_URL');

// Без API_URL: Android-эмулятор видит компьютер как 10.0.2.2, iOS-симулятор — как 127.0.0.1
final String baseUrl =
    _apiUrl.isNotEmpty ? _apiUrl : (Platform.isAndroid ? 'http://10.0.2.2:8000' : 'http://127.0.0.1:8000');
