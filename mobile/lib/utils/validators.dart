final emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

// Те же правила для логина, что и на сервере
final loginRe = RegExp(r'^[A-Za-z0-9_.-]{3,30}$');
