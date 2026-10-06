import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

// Адрес задаётся при сборке: flutter run --dart-define=API_URL=https://api.example.com
const String baseUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:8000');

void main() => runApp(const UNIvoiceApp());

// ==================== ТЕМА (тёмная, минималистичная) ====================
const kBg = Color(0xFF0D0D12);
const kSurface = Color(0xFF16161D);
const kSurface2 = Color(0xFF1E1E27);
const kBorder = Color(0xFF2B2B36);
const kAccent = Color(0xFF9D8CFF);
const kMuted = Color(0xFF8B8B9A);
const kText = Color(0xFFEDEDF2);
const kStatuses = ['Новое', 'Назначено', 'В работе', 'Решено', 'Закрыто'];

class _SoftTransitions extends PageTransitionsBuilder {
  const _SoftTransitions();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(curved),
        child: child,
      ),
    );
  }
}

ThemeData buildTheme() {
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  OutlineInputBorder border(Color c) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c));
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: kBg,
    colorScheme: const ColorScheme.dark(
        primary: kAccent, onPrimary: Color(0xFF14121F), secondary: kAccent, surface: kSurface, onSurface: kText),
    pageTransitionsTheme: const PageTransitionsTheme(
        builders: {TargetPlatform.android: _SoftTransitions(), TargetPlatform.iOS: _SoftTransitions()}),
    appBarTheme: const AppBarTheme(
      backgroundColor: kBg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: kText),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kSurface,
      border: border(kBorder),
      enabledBorder: border(kBorder),
      focusedBorder: border(kAccent),
      prefixIconColor: kMuted,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
          backgroundColor: kAccent, foregroundColor: const Color(0xFF14121F), elevation: 0, shape: shape),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(foregroundColor: kText, side: const BorderSide(color: kBorder), shape: shape),
    ),
  );
}

// Плавное появление снизу; чем больше index, тем позже «доезжает» элемент
class FadeIn extends StatelessWidget {
  final Widget child;
  final int index;
  const FadeIn({super.key, required this.child, this.index = 0});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 350 + index.clamp(0, 8) * 80),
        curve: Curves.easeOutCubic,
        builder: (_, v, c) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 16 * (1 - v)), child: c)),
        child: child,
      );
}

// Фото с сервера: ссылки вида /attachments/{id} защищены, поэтому нужен viewer_id
class NetImage extends StatelessWidget {
  final String path;
  final int viewerId;
  final BoxFit fit;
  const NetImage(this.path, this.viewerId, {super.key, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) => Image.network(
        '$baseUrl$path?viewer_id=$viewerId',
        headers: Api.token == null ? null : {'Authorization': 'Bearer ${Api.token}'},
        fit: fit,
        frameBuilder: (_, child, frame, sync) => sync
            ? child
            : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 350), child: child),
        loadingBuilder: (_, child, p) =>
            p == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined, color: kMuted)),
      );
}

void openPhoto(BuildContext context, String path, int viewerId) {
  Navigator.push(
    context,
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, _, __) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: Hero(tag: path, child: InteractiveViewer(child: NetImage(path, viewerId, fit: BoxFit.contain))),
          ),
        ),
      ),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ),
  );
}

List<String> _urls(dynamic l) =>
    l is List ? [for (final a in l) if (a is Map && a['url'] is String) a['url'] as String] : [];

List<({String label, String url})> _reportPhotos(dynamic r) {
  if (r is! Map || r['photos'] is! List) return [];
  return [
    for (final p in r['photos'])
      if (p is Map && p['url'] is String && p['source'] == 'employee')
        (label: p['kind'] == 'before' ? 'До' : 'После', url: p['url'] as String),
  ];
}

class UNIvoiceApp extends StatelessWidget {
  const UNIvoiceApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'UNIvoice',
        theme: buildTheme(),
        home: const AuthChoiceScreen(),
      );
}

// ==================== МОДЕЛИ ====================
class User {
  final int id;
  final String displayName, email, role;
  User({required this.id, required this.displayName, required this.email, required this.role});

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'] as int, // если id нет — бросим исключение, а не подставим чужой id
        displayName: j['display_name'] ?? 'Пользователь',
        email: j['email'] ?? 'не указан',
        role: j['role'] ?? 'student',
      );

  bool get isStaff => role == 'admin' || role == 'employee';
}

String fmtDate(DateTime? d) {
  if (d == null) return '—';
  final l = d.toLocal();
  String t(int n) => n.toString().padLeft(2, '0');
  return '${t(l.day)}.${t(l.month)}.${l.year} ${t(l.hour)}:${t(l.minute)}';
}

class Incident {
  final int id;
  final String title, type, category, status, description;
  final int? studentId;
  final bool isMine;
  final String? response;
  final String? assignee;
  final DateTime? createdAt;
  final List<String> photos;
  final List<({String label, String url})> reportPhotos;

  Incident.fromJson(Map<String, dynamic> j, int me)
      : id = j['id'] as int,
        title = j['title'] ?? 'Без заголовка',
        type = j['type'] ?? '',
        category = j['category'] ?? 'Не указана',
        status = j['status'] ?? 'Новое',
        description = j['description'] ?? 'Описание отсутствует',
        studentId = j['student_id'] as int?,
        isMine = j['is_mine'] ?? (j['student_id'] == me),
        response = j['response'] as String?,
        assignee = j['assigned_employee_name'] as String?,
        createdAt = DateTime.tryParse('${j['created_at'] ?? ''}'),
        photos = _urls(j['attachments']),
        reportPhotos = _reportPhotos(j['response_report']);
}

// ==================== API ====================
class ApiResult {
  final int status; // 0 = нет связи / таймаут
  final dynamic data;
  ApiResult(this.status, this.data);

  bool get ok => status >= 200 && status < 300;
  String error(String fallback) => data is Map && data['detail'] != null ? '${data['detail']}' : fallback;
}

class Api {
  // В памяти. Для сохранения между запусками — flutter_secure_storage.
  static String? token;

  static Future<ApiResult> get(String path) => _send('GET', path);
  static Future<ApiResult> post(String path, Map<String, dynamic> body) => _send('POST', path, body);
  static Future<ApiResult> delete(String path, [Map<String, dynamic>? body]) => _send('DELETE', path, body);
  static Future<ApiResult> patch(String path, Map<String, dynamic> body) => _send('PATCH', path, body);

  // Загрузка фото: POST multipart/form-data, поле файла называется 'file'
  static Future<ApiResult> uploadImage(String path, Map<String, String> fields, File file, {String field = 'file'}) async {
    try {
      final req = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'))
        ..fields.addAll(fields)
        ..files.add(await http.MultipartFile.fromPath(field, file.path));
      if (token != null) req.headers['Authorization'] = 'Bearer $token';
      final r = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 30)));
      dynamic data;
      try {
        data = r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
      } catch (_) {}
      return ApiResult(r.statusCode, data);
    } on TimeoutException {
      return ApiResult(0, {'detail': 'Сервер не отвечает'});
    } catch (_) {
      return ApiResult(0, {'detail': 'Нет связи с сервером'});
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
      return ApiResult(0, {'detail': 'Сервер не отвечает'});
    } catch (_) {
      return ApiResult(0, {'detail': 'Нет связи с сервером'});
    }
  }
}

// ==================== ОБЩЕЕ ====================
mixin SafeState<T extends StatefulWidget> on State<T> {
  void safeSetState(VoidCallback fn) {
    if (mounted) setState(fn);
  }
}

void snack(BuildContext c, String text, {Color? color, int ms = 2500}) {
  ScaffoldMessenger.of(c)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(text), backgroundColor: color, duration: Duration(milliseconds: ms)));
}

class StatusText extends StatelessWidget {
  final String text;
  final bool ok;
  const StatusText(this.text, {super.key, this.ok = false});

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: Text(
          text,
          key: ValueKey(text),
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w500, color: ok ? const Color(0xFF6EE7A8) : const Color(0xFFFF7A8A)),
        ),
      );
}

final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

// Отладочная иконка проверки связи — в релизе не показывается
class ApiStatusIcon extends StatefulWidget {
  const ApiStatusIcon({super.key});

  @override
  State<ApiStatusIcon> createState() => _ApiStatusIconState();
}

class _ApiStatusIconState extends State<ApiStatusIcon> with SafeState<ApiStatusIcon> {
  bool _online = false, _loading = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check({bool manual = false}) async {
    safeSetState(() => _loading = true);
    if (manual) snack(context, 'Проверка соединения...', ms: 800);
    final r = await Api.get('/');
    if (!mounted) return;
    setState(() {
      _online = r.ok;
      _loading = false;
    });
    if (manual) {
      snack(
        context,
        r.ok
            ? 'Бэкенд онлайн ($baseUrl)'
            : r.status == 0
                ? r.error('Нет связи с сервером')
                : 'Сервер ответил кодом ${r.status}',
        color: r.ok ? Colors.green : Colors.red,
        ms: 2000,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    return IconButton(
      icon: _loading
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(Icons.router, color: _online ? Colors.green : Colors.redAccent),
      tooltip: _online ? 'Бэкенд онлайн' : 'Бэкенд недоступен',
      onPressed: _loading ? null : () => _check(manual: true),
    );
  }
}

// ==================== ВЫБОР: ВХОД / РЕГИСТРАЦИЯ ====================
// Геометрическая иллюстрация (круги, полукруги, четверти и волнистые линии)
class HeroArt extends CustomPainter {
  static const _cols = [kAccent, Color(0xFF4B3FBF), Color(0xFF2A2560), Color(0xFF7AB8FF), Color(0xFF1F1B45), Color(0xFFB7A9FF)];

  @override
  void paint(Canvas c, Size s) {
    final u = s.width / 3;
    final p = Paint();
    for (var r = 0; r < (s.height / u).ceil(); r++) {
      for (var q = 0; q < 3; q++) {
        final i = r * 3 + q;
        final rect = Rect.fromLTWH(q * u, r * u, u, u).deflate(3);
        p.color = _cols[(i * 5) % 6];
        switch (i % 4) {
          case 0:
            c.drawCircle(rect.center, rect.width / 2, p);
          case 1:
            c.drawArc(rect, 0, math.pi, true, p);
          case 2:
            c.drawArc(rect, math.pi, math.pi, true, p);
          default:
            c.drawRRect(RRect.fromRectAndCorners(rect, topRight: Radius.circular(rect.width)), p);
        }
      }
    }
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = const Color(0x88EDEDF2);
    for (var i = 0; i < 5; i++) {
      final dx = i * 9.0;
      c.drawPath(
        Path()
          ..moveTo(u * 0.9 + dx, 0)
          ..cubicTo(u * 0.9 + dx, u * 1.2, u * 2.0 + dx, u * 1.0, u * 2.0 + dx, u * 2.0)
          ..cubicTo(u * 2.0 + dx, u * 2.6, u * 1.2 + dx, u * 2.5, u * 1.2 + dx, s.height),
        line,
      );
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

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

// ==================== ВХОД ====================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SafeState<LoginScreen> {
  final _loginC = TextEditingController();
  final _passC = TextEditingController();
  String _msg = '';
  bool _loading = false;

  @override
  void dispose() {
    _loginC.dispose();
    _passC.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_loginC.text.trim().isEmpty || _passC.text.isEmpty) {
      setState(() => _msg = 'Введите логин и пароль');
      return;
    }
    setState(() {
      _loading = true;
      _msg = '';
    });

    final r = await Api.post('/auth/login', {'login': _loginC.text.trim(), 'password': _passC.text});
    if (!mounted) return;

    if (r.ok && r.data is Map && r.data['user'] is Map) {
      try {
        final user = User.fromJson(Map<String, dynamic>.from(r.data['user']));
        Api.token = r.data['access_token'];
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => HomeScreen(user: user)),
          (_) => false,
        );
        return;
      } catch (_) {}
    }
    setState(() {
      _loading = false;
      _msg = r.ok ? 'Некорректный ответ сервера' : 'Ошибка входа: ${r.error('Неверные данные')}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Вход в систему')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _loginC,
              decoration: const InputDecoration(labelText: 'Логин', prefixIcon: Icon(Icons.person)),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passC,
              decoration: const InputDecoration(labelText: 'Пароль', prefixIcon: Icon(Icons.lock)),
              obscureText: true,
              onSubmitted: (_) => _loading ? null : _login(),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loading ? null : _login,
              icon: const Icon(Icons.login),
              label: const Text('Войти'),
            ),
            const SizedBox(height: 20),
            StatusText(_msg),
          ],
        ),
      ),
    );
  }
}

// ==================== РЕГИСТРАЦИЯ ====================
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
    if (!_emailRe.hasMatch(_emailC.text.trim())) {
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
        _msg = 'Регистрация успешна!';
      });
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) Navigator.pop(context);
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
          ],
        ),
      ),
    );
  }
}

// ==================== ГЛАВНЫЙ ЭКРАН ====================
class HomeScreen extends StatefulWidget {
  final User user;
  const HomeScreen({super.key, required this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  String? _filter;

  void _go(int tab, {String? filter}) => setState(() {
        _tab = tab;
        _filter = filter;
      });

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    final pages = [
      DashboardTab(user: u, onOpenFeed: (f) => _go(1, filter: f), onCreate: () => _go(2)),
      IncidentsListScreen(user: u, initialFilter: _filter),
      CreateIncidentScreen(user: u),
      ProfileTab(user: u),
    ];
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOutCubic,
        child: KeyedSubtree(key: ValueKey('$_tab$_filter'), child: pages[_tab]),
      ),
      bottomNavigationBar: _NavBar(index: _tab, onTap: (i) => _go(i)),
    );
  }
}

class _NavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _NavBar({required this.index, required this.onTap});

  static const _off = [Icons.home_outlined, Icons.list_alt_outlined, Icons.add_circle_outline, Icons.person_outline];
  static const _on = [Icons.home, Icons.list_alt, Icons.add_circle, Icons.person];
  static const _names = ['Главная', 'Лента', 'Создать', 'Профиль'];

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(color: kSurface, border: Border(top: BorderSide(color: kBorder))),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                for (var i = 0; i < 4; i++)
                  Expanded(
                    child: InkResponse(
                      onTap: () => onTap(i),
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                          decoration: BoxDecoration(
                            color: index == i ? const Color(0x269D8CFF) : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(index == i ? _on[i] : _off[i],
                              semanticLabel: _names[i], color: index == i ? kAccent : kMuted),
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

class _Ripples extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0x1AFFFFFF);
    for (var i = 1; i <= 7; i++) {
      c.drawCircle(Offset(s.width, 0), i * 34.0, p);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

class DashboardTab extends StatefulWidget {
  final User user;
  final ValueChanged<String?> onOpenFeed;
  final VoidCallback onCreate;
  const DashboardTab({super.key, required this.user, required this.onOpenFeed, required this.onCreate});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  List<Incident>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Api.get('/incidents?viewer_id=${widget.user.id}');
    if (!mounted || !r.ok || r.data is! List) return;
    try {
      final l = (r.data as List).map((j) => Incident.fromJson(Map<String, dynamic>.from(j), widget.user.id)).toList();
      setState(() => _items = l);
    } catch (_) {}
  }

  int _count(String? status) {
    final l = _items;
    if (l == null) return -1;
    return status == null ? l.length : l.where((i) => i.status == status).length;
  }

  Widget _tile(String label, String? status, double h, {bool accent = false}) {
    final n = _count(status);
    const big = TextStyle(fontSize: 34, fontWeight: FontWeight.w700);
    return GestureDetector(
      onTap: () => widget.onOpenFeed(status),
      child: Container(
        height: h,
        width: double.infinity,
        decoration: BoxDecoration(
          color: accent ? const Color(0xFF3B31B0) : kSurface,
          borderRadius: BorderRadius.circular(22),
          border: accent ? null : Border.all(color: kBorder),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            n < 0
                ? const Text('–', style: big)
                : TweenAnimationBuilder<int>(
                    tween: IntTween(begin: 0, end: n),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) => Text('$v', style: big),
                  ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 13, color: accent ? const Color(0xCCFFFFFF) : kMuted)),
          ],
        ),
      ),
    );
  }

  Widget _featured(BuildContext context) {
    final l = _items;
    if (l == null) return const SizedBox(height: 8);
    final inc = l.isEmpty ? null : l.first;
    return GestureDetector(
      onTap: inc == null
          ? widget.onCreate
          : () => Navigator.push(context, MaterialPageRoute(builder: (_) => IncidentDetailScreen(incident: inc, user: widget.user)))
              .then((_) => _load()),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 24),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0x26FFFFFF), borderRadius: BorderRadius.circular(18)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(inc?.title ?? 'Создать первое обращение',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(inc == null ? 'Жалоба или предложение — это займёт минуту' : '${inc.type} · ${inc.category}',
                      style: const TextStyle(fontSize: 13, color: Color(0xB3FFFFFF))),
                ],
              ),
            ),
            const SizedBox(width: 12),
            inc == null
                ? const Icon(Icons.arrow_forward)
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(10)),
                    child: Text(inc.status, style: const TextStyle(fontSize: 12)),
                  ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    final active = _items?.where((i) => i.status != 'Решено' && i.status != 'Закрыто').length;
    final first = u.displayName.trim().split(' ').first;
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF4A3FC4), Color(0xFF1B1745)]),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(child: CustomPaint(painter: _Ripples())),
                    Padding(
                      padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 24, 24, 28),
                      child: FadeIn(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Привет, $first',
                                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 4),
                                      Text(
                                        active == null
                                            ? 'Загружаем обращения…'
                                            : active == 0
                                                ? 'Нет активных обращений'
                                                : 'Активных обращений: $active',
                                        style: const TextStyle(color: Color(0xB3FFFFFF)),
                                      ),
                                    ],
                                  ),
                                ),
                                CircleAvatar(
                                  radius: 22,
                                  backgroundColor: const Color(0x33FFFFFF),
                                  child: Text(first.isEmpty ? '?' : first[0].toUpperCase(),
                                      style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                                ),
                              ],
                            ),
                            _featured(context),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Обзор', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(children: [
                          FadeIn(index: 1, child: _tile('Всего', null, 130, accent: true)),
                          const SizedBox(height: 12),
                          FadeIn(index: 3, child: _tile('В работе', 'В работе', 100)),
                        ]),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(children: [
                          FadeIn(index: 2, child: _tile('Новые', 'Новое', 100)),
                          const SizedBox(height: 12),
                          FadeIn(index: 4, child: _tile('Решено', 'Решено', 130)),
                        ]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
      appBar: AppBar(title: const Text('Профиль'), actions: const [ApiStatusIcon()]),
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

// ==================== ЛЕНТА ОБРАЩЕНИЙ ====================
class IncidentsListScreen extends StatefulWidget {
  final User user;
  final String? initialFilter;
  const IncidentsListScreen({super.key, required this.user, this.initialFilter});

  @override
  State<IncidentsListScreen> createState() => _IncidentsListScreenState();
}

class _IncidentsListScreenState extends State<IncidentsListScreen> with SafeState<IncidentsListScreen> {
  List<Incident> _items = [];
  bool _loading = true;
  String _error = '';
  late String? _filter = widget.initialFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Api.get('/incidents?viewer_id=${widget.user.id}');
    if (!mounted) return;
    if (r.ok && r.data is List) {
      try {
        final list = (r.data as List).map((j) => Incident.fromJson(Map<String, dynamic>.from(j), widget.user.id)).toList();
        setState(() {
          _items = list;
          _error = '';
          _loading = false;
        });
        return;
      } catch (_) {}
    }
    setState(() {
      _error = r.ok ? 'Некорректный ответ сервера' : 'Ошибка загрузки: ${r.error('код ${r.status}')}';
      _loading = false;
    });
  }

  Future<void> _open(Incident inc) async {
    final deleted = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => IncidentDetailScreen(incident: inc, user: widget.user)));
    if (!mounted) return;
    if (deleted == true) snack(context, 'Обращение удалено');
    _load();
  }

  Future<void> _delete(Incident inc, {String? reason}) async {
    final r = widget.user.role == 'admin'
        ? await Api.delete('/admin/incidents/${inc.id}', {'admin_id': widget.user.id, 'reason': reason ?? ''})
        : await Api.delete('/incidents/${inc.id}?student_id=${widget.user.id}');
    if (!mounted) return;
    if (r.ok) {
      setState(() => _items.removeWhere((i) => i.id == inc.id));
      snack(context, 'Обращение успешно удалено');
    } else {
      snack(context, 'Не удалось удалить: ${r.error('Ошибка прав')}');
    }
  }

  Future<void> _confirmDelete(Incident inc) async {
    final isAdmin = widget.user.role == 'admin';
    final reasonC = TextEditingController(); // короткоживущий, dispose не нужен
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAdmin ? 'Скрыть обращение' : 'Отмена обращения'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(isAdmin ? 'Укажите причину (мин. 5 символов):' : 'Вы действительно хотите отменить это обращение?'),
            if (isAdmin) TextField(controller: reasonC, maxLength: 500, maxLines: 2),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Назад')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isAdmin ? 'Скрыть' : 'Отменить', style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final reason = reasonC.text.trim();
    if (isAdmin && reason.length < 5) {
      snack(context, 'Причина должна быть не короче 5 символов');
      return;
    }
    _delete(inc, reason: reason);
  }

  Widget _card(Incident inc) {
    final u = widget.user;
    final canDelete = u.role == 'admin' || (u.role == 'student' && inc.isMine && inc.status == 'Новое');
    final isComplaint = inc.type == 'Жалоба';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: inc.isMine ? const Color(0xFF2E2680) : kSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: inc.isMine ? Colors.transparent : kBorder),
      ),
      child: ListTile(
        onTap: () => _open(inc),
        leading: inc.photos.isEmpty
            ? Icon(isComplaint ? Icons.report_problem_outlined : Icons.lightbulb_outline,
                color: isComplaint ? const Color(0xFFFF7A8A) : const Color(0xFF7AB8FF))
            : ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(width: 52, height: 52, child: NetImage(inc.photos.first, widget.user.id)),
              ),
        title: Text(inc.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('Категория: ${inc.category}\nСтатус: ${inc.status}\n${fmtDate(inc.createdAt)}'),
            if (inc.isMine)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('★ Ваше обращение',
                    style: TextStyle(color: Color(0xFFD9D2FF), fontWeight: FontWeight.w600, fontSize: 12)),
              ),
          ],
        ),
        trailing: canDelete
            ? IconButton(
                icon: const Icon(Icons.delete_outline, color: kMuted),
                tooltip: 'Удалить',
                onPressed: () => _confirmDelete(inc),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = _filter == null ? _items : _items.where((i) => i.status == _filter).toList();
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error.isNotEmpty) {
      body = ListView(children: [
        Padding(padding: const EdgeInsets.all(24), child: Center(child: StatusText(_error))),
      ]);
    } else if (shown.isEmpty) {
      body = ListView(children: const [Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Список обращений пуст')))]);
    } else {
      body = ListView.builder(itemCount: shown.length, itemBuilder: (_, i) => FadeIn(index: i, child: _card(shown[i])));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Лента обращений')),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final f in <String?>[null, ...kStatuses])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f ?? 'Все'),
                      selected: _filter == f,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _filter = f),
                      selectedColor: kAccent,
                      backgroundColor: kSurface,
                      side: const BorderSide(color: kBorder),
                      shape: const StadiumBorder(),
                      labelStyle: TextStyle(
                          color: _filter == f ? const Color(0xFF14121F) : kText, fontWeight: FontWeight.w500),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: KeyedSubtree(key: ValueKey(_filter), child: body),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== ДЕТАЛИ ОБРАЩЕНИЯ ====================
class IncidentDetailScreen extends StatefulWidget {
  final Incident incident;
  final User user;
  const IncidentDetailScreen({super.key, required this.incident, required this.user});

  @override
  State<IncidentDetailScreen> createState() => _IncidentDetailScreenState();
}

class _IncidentDetailScreenState extends State<IncidentDetailScreen> {
  late Incident incident = widget.incident;
  User get user => widget.user;
  bool _busy = false;

  // ---------- диалоги ----------
  Future<bool> _confirm(String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(text),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Да')),
          ],
        ),
      ) ==
      true;

  Future<String?> _ask(String title, String hint, {int min = 0, TextInputType? type, String? initial}) async {
    final c = TextEditingController(text: initial);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true, keyboardType: type, decoration: InputDecoration(hintText: hint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Назад')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Готово')),
        ],
      ),
    );
    final v = c.text.trim();
    if (ok != true || !mounted) return null;
    if (v.length < min) {
      snack(context, 'Минимум символов: $min');
      return null;
    }
    return v;
  }

  // ---------- действия ----------
  void _apply(ApiResult r, String okText) {
    if (!mounted) return;
    if (r.ok && r.data is Map) {
      setState(() {
        incident = Incident.fromJson(Map<String, dynamic>.from(r.data), user.id);
        _busy = false;
      });
      snack(context, okText);
    } else {
      setState(() => _busy = false);
      snack(context, r.error('Не удалось выполнить действие'));
    }
  }

  Future<void> _status(String status, {String? reason, int? employeeId}) async {
    setState(() => _busy = true);
    final r = await Api.patch('/incidents/${incident.id}/status', {
      'status': status,
      if (reason != null) 'reason': reason,
      if (employeeId != null) 'assigned_employee_id': employeeId,
    });
    _apply(r, 'Статус: $status');
  }

  Future<void> _assign() async {
    final v = await _ask('Назначить сотрудника', 'ID сотрудника', type: TextInputType.number, initial: '2');
    if (v == null) return;
    final id = int.tryParse(v);
    if (id == null) {
      snack(context, 'Введите числовой ID сотрудника');
      return;
    }
    _status('Назначено', employeeId: id);
  }

  Future<void> _reopen() async {
    final v = await _ask('Вернуть на доработку', 'Что не так? (причина)', min: 3);
    if (v != null) _status('Новое', reason: v);
  }

  Future<void> _finish() async {
    final c = TextEditingController();
    File? photo;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSurface,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          Future<void> pick(ImageSource src) async {
            final x = await ImagePicker().pickImage(source: src, imageQuality: 85, maxWidth: 1600, maxHeight: 1600);
            if (x != null) set(() => photo = File(x.path));
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Фотоотчёт', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                TextField(controller: c, maxLines: 3, decoration: const InputDecoration(hintText: 'Комментарий (необязательно)')),
                const SizedBox(height: 12),
                Text(photo == null ? 'Фото «после» (обязательно)' : 'Фото выбрано', style: const TextStyle(color: kMuted)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: OutlinedButton.icon(onPressed: () => pick(ImageSource.camera), icon: const Icon(Icons.camera_alt_outlined), label: const Text('Камера'))),
                  const SizedBox(width: 10),
                  Expanded(child: OutlinedButton.icon(onPressed: () => pick(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined), label: const Text('Галерея'))),
                ]),
                const SizedBox(height: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: const StadiumBorder()),
                  onPressed: photo == null ? null : () => Navigator.pop(ctx, true),
                  child: const Text('Опубликовать и завершить'),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (ok != true || photo == null || !mounted) return;
    setState(() => _busy = true);
    final r = await Api.uploadImage(
      '/incidents/${incident.id}/response',
      {'employee_id': '${user.id}', if (c.text.trim().isNotEmpty) 'comment': c.text.trim()},
      photo!,
      field: 'after_photo',
    );
    _apply(r, 'Отчёт опубликован');
  }

  Future<void> _delete() async {
    final admin = user.role == 'admin';
    String? reason;
    if (admin) {
      reason = await _ask('Скрыть обращение', 'Причина (мин. 5 символов)', min: 5);
      if (reason == null) return;
    } else if (!await _confirm('Отменить это обращение?') || !mounted) {
      return;
    }
    setState(() => _busy = true);
    final r = admin
        ? await Api.delete('/admin/incidents/${incident.id}', {'admin_id': user.id, 'reason': reason})
        : await Api.delete('/incidents/${incident.id}?student_id=${user.id}');
    if (!mounted) return;
    if (r.ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _busy = false);
      snack(context, r.error('Не удалось удалить'));
    }
  }

  // ---------- панель кнопок внизу ----------
  Widget _btn(String label, IconData icon, VoidCallback f, {bool primary = false, bool danger = false}) {
    final pad = const EdgeInsets.symmetric(vertical: 16);
    final onTap = _busy ? null : f;
    return primary
        ? ElevatedButton.icon(
            onPressed: onTap,
            icon: Icon(icon, size: 20),
            label: Text(label),
            style: ElevatedButton.styleFrom(padding: pad, shape: const StadiumBorder()),
          )
        : OutlinedButton.icon(
            onPressed: onTap,
            icon: Icon(icon, size: 20),
            label: Text(label),
            style: OutlinedButton.styleFrom(
              padding: pad,
              shape: const StadiumBorder(),
              foregroundColor: danger ? const Color(0xFFFF7A8A) : kText,
              side: BorderSide(color: danger ? const Color(0x66FF7A8A) : kBorder),
            ),
          );
  }

  Widget _actionBar() {
    final u = user, s = incident.status, complaint = incident.type == 'Жалоба';
    final mine = u.role == 'student' && incident.isMine;
    final acts = <Widget>[
      if (u.role == 'admin' && s == 'Новое' && complaint) _btn('Назначить сотрудника', Icons.person_add_alt, _assign, primary: true),
      if (u.role == 'employee' && s == 'Назначено') _btn('Взять в работу', Icons.play_arrow_rounded, () => _status('В работе'), primary: true),
      if (u.role == 'employee' && s == 'В работе' && complaint) _btn('Завершить с фотоотчётом', Icons.task_alt, _finish, primary: true),
      if (mine && s == 'Решено') ...[
        _btn('Принять и закрыть', Icons.check, () => _status('Закрыто'), primary: true),
        _btn('Вернуть на доработку', Icons.replay, _reopen),
      ],
      if ((mine && s == 'Новое') || u.role == 'admin')
        _btn(u.role == 'admin' ? 'Скрыть обращение' : 'Отменить обращение', Icons.delete_outline, _delete, danger: true),
    ];
    if (acts.isEmpty) return const SizedBox.shrink();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [for (final a in acts) Padding(padding: const EdgeInsets.only(top: 8), child: SizedBox(width: double.infinity, child: a))],
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 6),
        child: Text(t, style: const TextStyle(fontSize: 12, letterSpacing: 0.8, color: kMuted)),
      );

  Widget _box(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kBorder),
        ),
        child: child,
      );

  Widget _gallery(BuildContext context, List<({String label, String url})> items) => SizedBox(
        height: 150,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) => GestureDetector(
            onTap: () => openPhoto(context, items[i].url, user.id),
            child: Hero(
              tag: items[i].url,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 200,
                  color: kSurface,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      NetImage(items[i].url, user.id),
                      if (items[i].label.isNotEmpty)
                        Positioned(
                          left: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                            child: Text(items[i].label, style: const TextStyle(fontSize: 12, color: kText)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final photos = [for (final u in incident.photos) (label: '', url: u)];
    final hasResponse = (incident.response ?? '').isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(incident.title)),
      bottomNavigationBar: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: KeyedSubtree(key: ValueKey('${incident.status}$_busy'), child: _actionBar()),
      ),
      body: FadeIn(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (user.isStaff && incident.studentId != null) ...[
                _label('АВТОР (ID СТУДЕНТА)'),
                _box(Text('${incident.studentId}')),
              ],
              _label('ТИП'),
              Text(incident.type, style: const TextStyle(fontSize: 16)),
              _label('КАТЕГОРИЯ'),
              Text(incident.category, style: const TextStyle(fontSize: 16)),
              _label('СТАТУС'),
              Chip(label: Text(incident.status), backgroundColor: kSurface2, side: const BorderSide(color: kBorder)),
              if (incident.assignee != null) ...[
                _label('ИСПОЛНИТЕЛЬ'),
                Text(incident.assignee!, style: const TextStyle(fontSize: 16)),
              ],
              _label('СОЗДАНО'),
              Text(fmtDate(incident.createdAt), style: const TextStyle(fontSize: 16)),
              _label('ОПИСАНИЕ'),
              _box(Text(incident.description, style: const TextStyle(fontSize: 16, height: 1.5))),
              if (photos.isNotEmpty) ...[
                _label('ФОТО'),
                _gallery(context, photos),
              ],
              if (hasResponse || incident.reportPhotos.isNotEmpty) ...[
                _label('ОТВЕТ СОТРУДНИКА'),
                if (hasResponse) _box(Text(incident.response!, style: const TextStyle(fontSize: 16, height: 1.5))),
                if (incident.reportPhotos.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _gallery(context, incident.reportPhotos),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== СОЗДАНИЕ ОБРАЩЕНИЯ ====================
class CreateIncidentScreen extends StatefulWidget {
  final User user;
  const CreateIncidentScreen({super.key, required this.user});

  @override
  State<CreateIncidentScreen> createState() => _CreateIncidentScreenState();
}

class _CreateIncidentScreenState extends State<CreateIncidentScreen> with SafeState<CreateIncidentScreen> {
  String _type = 'Жалоба';
  String _category = 'оборудование';
  final _titleC = TextEditingController();
  final _descC = TextEditingController();
  final _picker = ImagePicker();
  String _msg = '';
  bool _ok = false, _sending = false;
  File? _image;

  @override
  void dispose() {
    _titleC.dispose();
    _descC.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final file = await _picker.pickImage(source: source, imageQuality: 85, maxWidth: 1600, maxHeight: 1600);
      if (file != null) safeSetState(() => _image = File(file.path));
    } catch (e) {
      if (mounted) snack(context, 'Не удалось получить фото. Проверьте разрешения приложения.');
    }
  }

  Future<void> _submit() async {
    if (_titleC.text.trim().length < 5 || _descC.text.trim().length < 20) {
      setState(() {
        _ok = false;
        _msg = 'Заполните заголовок (мин.5) и описание (мин.20)';
      });
      return;
    }
    setState(() {
      _sending = true;
      _msg = '';
    });

    final r = await Api.post('/incidents', {
      'student_id': widget.user.id,
      'type': _type,
      'category': _category,
      'title': _titleC.text.trim(),
      'description': _descC.text.trim(),
    });
    if (!mounted) return;

    String? photoError;
    if (r.status == 201 && _image != null && r.data is Map) {
      final up = await Api.uploadImage(
        '/incidents/${r.data['id']}/attachments',
        {'student_id': '${widget.user.id}'},
        _image!,
      );
      if (!mounted) return;
      if (!up.ok) photoError = up.error('ошибка загрузки');
    }

    setState(() {
      _sending = false;
      _ok = r.status == 201;
      _msg = !_ok
          ? 'Ошибка: ${r.error('Не удалось создать')}'
          : photoError == null
              ? 'Обращение успешно создано!'
              : 'Обращение создано, но фото не загружено: $photoError';
      if (_ok) {
        _titleC.clear();
        _descC.clear();
        _image = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Новое обращение')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              value: _type,
              items: const [
                DropdownMenuItem(value: 'Жалоба', child: Text('Жалоба')),
                DropdownMenuItem(value: 'Предложение', child: Text('Предложение')),
              ],
              onChanged: (v) => setState(() => _type = v ?? _type),
              decoration: const InputDecoration(labelText: 'Тип обращения', prefixIcon: Icon(Icons.category)),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _category,
              items: const [
                DropdownMenuItem(value: 'оборудование', child: Text('Оборудование')),
                DropdownMenuItem(value: 'учебный процесс', child: Text('Учебный процесс')),
                DropdownMenuItem(value: 'инфраструктура', child: Text('Инфраструктура')),
              ],
              onChanged: (v) => setState(() => _category = v ?? _category),
              decoration: const InputDecoration(labelText: 'Категория', prefixIcon: Icon(Icons.folder)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleC,
              decoration: const InputDecoration(labelText: 'Заголовок (мин. 5 символов)', prefixIcon: Icon(Icons.title)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descC,
              decoration: const InputDecoration(
                labelText: 'Описание (минимум 20 символов)',
                prefixIcon: Icon(Icons.description),
                helperText: 'Опишите проблему подробно',
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 16),
            const Text('Доказательства (фото):', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: kSurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: kBorder),
                  ),
                  child: AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: _image == null
                      ? const Center(key: ValueKey('empty'), child: Icon(Icons.photo_camera_outlined, size: 36, color: kMuted))
                      : ClipRRect(key: ValueKey(_image!.path), borderRadius: BorderRadius.circular(8), child: Image.file(_image!, fit: BoxFit.cover, width: 100, height: 100))),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _pickImage(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Сделать фото'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: kSurface2,
                            foregroundColor: kText,
                            minimumSize: const Size(double.infinity, 40)),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => _pickImage(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Выбрать из галереи'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 40)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_image != null)
              TextButton(
                onPressed: () => setState(() => _image = null),
                child: const Text('Удалить фото', style: TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _sending ? null : _submit,
              icon: const Icon(Icons.send),
              label: const Text('Отправить обращение'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(12)),
            ),
            const SizedBox(height: 16),
            StatusText(_msg, ok: _ok),
          ],
        ),
      ),
    );
  }
}