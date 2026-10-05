import 'dart:convert';
import 'dart:io'; // Для работы с File
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart'; // Импорт пакета для выбора изображений

// Базовый адрес бэкенда для Android-эмулятора
const String baseUrl = 'http://10.0.2.2:8000';

void main() {
  runApp(const UNIvoiceApp());
}

class UNIvoiceApp extends StatelessWidget {
  const UNIvoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UNIvoice',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const AuthChoiceScreen(),
    );
  }
}

// ==================== ГЛОБАЛЬНЫЙ ВИДЖЕТ ТЕСТА СВЯЗИ ====================
class ApiStatusIcon extends StatefulWidget {
  const ApiStatusIcon({super.key});

  @override
  State<ApiStatusIcon> createState() => _ApiStatusIconState();
}

class _ApiStatusIconState extends State<ApiStatusIcon> {
  bool _isOnline = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkHealth();
  }

  Future<void> _checkHealth() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse('$baseUrl/health')).timeout(const Duration(seconds: 3));
      setState(() {
        _isOnline = response.statusCode == 200;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isOnline = false;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: _isLoading
          ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white60))
          : Icon(Icons.router, color: _isOnline ? Colors.greenAccent : Colors.redAccent),
      tooltip: _isOnline ? 'Бэкенд онлайн' : 'Бэкенд недоступен (нажмите для проверки)',
      onPressed: _isLoading ? null : _checkHealth,
    );
  }
}

// ==================== ЭКРАН ВЫБОРА (ВХОД / РЕГИСТРАЦИЯ) ====================
class AuthChoiceScreen extends StatelessWidget {
  const AuthChoiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.campaign, size: 80, color: Colors.deepPurple),
              const SizedBox(height: 16),
              const Text(
                'UNIvoice',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.deepPurple),
              ),
              const SizedBox(height: 8),
              const Text(
                'Сервис студенческих обращений',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 48),

              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
                },
                icon: const Icon(Icons.login),
                label: const Text('Войти в аккаунт', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 16),

              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  side: const BorderSide(color: Colors.deepPurple),
                ),
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const RegisterScreen()));
                },
                icon: const Icon(Icons.person_add),
                label: const Text('Зарегистрироваться', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 24),
              const Center(child: ApiStatusIcon()),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== ЭКРАН АВТОРИЗАЦИИ ====================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  String _resultMessage = '';
  bool _isLoading = false;

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _resultMessage = '';
    });

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'login': _loginController.text.trim(),
          'password': _passwordController.text,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => HomeScreen(userData: data['user'])),
          (route) => false,
        );
      } else {
        setState(() {
          _resultMessage = 'Ошибка входа: ${data['detail'] ?? 'Неверные данные'}';
        });
      }
    } catch (e) {
      setState(() {
        _resultMessage = 'Ошибка соединения: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Вход в систему')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'Введите логин (например, admin или student) и пароль:',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _loginController,
              decoration: const InputDecoration(labelText: 'Логин', prefixIcon: Icon(Icons.person)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Пароль', prefixIcon: Icon(Icons.lock)),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _login,
              icon: const Icon(Icons.login),
              label: const Text('Войти'),
            ),
            const SizedBox(height: 20),
            Text(_resultMessage, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
          ],
        ),
      ),
    );
  }
}

// ==================== ЭКРАН РЕГИСТРАЦИИ ====================
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _loginController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String _message = '';
  bool _isLoading = false;

  Future<void> _register() async {
    if (_loginController.text.trim().isEmpty ||
        _nameController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      setState(() {
        _message = 'Заполните все обязательные поля (*)!';
      });
      return;
    }

    if (_passwordController.text.length < 8) {
      setState(() {
        _message = 'Пароль должен быть не менее 8 символов!';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _message = '';
    });

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'login': _loginController.text.trim(),
          'display_name': _nameController.text.trim(),
          'email': _emailController.text.trim(),
          'password': _passwordController.text,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 201) {
        setState(() {
          _message = 'Регистрация успешна!';
        });
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        Navigator.pop(context);
      } else {
        setState(() {
          _message = 'Ошибка: ${data['detail'] ?? 'Не удалось зарегистрироваться'}';
        });
      }
    } catch (e) {
      setState(() {
        _message = 'Ошибка соединения: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Регистрация студента')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _loginController,
              decoration: const InputDecoration(labelText: 'Логин *', prefixIcon: Icon(Icons.account_circle)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'ФИО / Отображаемое имя *', prefixIcon: Icon(Icons.badge)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email *', prefixIcon: Icon(Icons.email)),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Пароль * (мин. 8 символов)', prefixIcon: Icon(Icons.lock_outline)),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _register,
              icon: const Icon(Icons.app_registration),
              label: const Text('Зарегистрироваться'),
            ),
            const SizedBox(height: 16),
            Text(_message, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: _message.contains('успешна') ? Colors.green : Colors.red)),
          ],
        ),
      ),
    );
  }
}

// ==================== ГЛАВНЫЙ ЭКРАН (ДАШБОРД) ====================
class HomeScreen extends StatelessWidget {
  final Map<String, dynamic> userData;

  const HomeScreen({super.key, required this.userData});

  @override
  Widget build(BuildContext context) {
    final String role = userData['role'] ?? 'student';
    final int userId = userData['id'] ?? 1;

    return Scaffold(
      appBar: AppBar(
        title: Text('Привет, ${userData['display_name'] ?? 'Пользователь'}!'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          const Center(child: ApiStatusIcon()), // Иконка проверки API в AppBar
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Выйти',
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const AuthChoiceScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Роль в системе: $role', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text('Email: ${userData['email'] ?? 'не указан'}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Разделы сервиса:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),

            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(14)),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => IncidentsListScreen(currentUserId: userId, userRole: role)),
              ),
              icon: const Icon(Icons.list_alt),
              label: const Text('Лента обращений', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 12),

            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(14),
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => CreateIncidentScreen(studentId: userId)),
              ),
              icon: const Icon(Icons.add_circle),
              label: const Text('Создать жалобу / предложение', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== ЭКРАН СПИСКА ОБРАЩЕНИЙ ====================
class IncidentsListScreen extends StatefulWidget {
  final int currentUserId;
  final String userRole;

  const IncidentsListScreen({super.key, required this.currentUserId, required this.userRole});

  @override
  State<IncidentsListScreen> createState() => _IncidentsListScreenState();
}

class _IncidentsListScreenState extends State<IncidentsListScreen> {
  List<dynamic> _incidents = [];
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchIncidents();
  }

  Future<void> _fetchIncidents() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/incidents?viewer_id=${widget.currentUserId}'));
      if (response.statusCode == 200) {
        setState(() {
          _incidents = jsonDecode(response.body);
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Ошибка загрузки: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Ошибка соединения: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteIncident(int incidentId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/incidents/$incidentId?user_id=${widget.currentUserId}'),
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        setState(() {
          _incidents.removeWhere((inc) => inc['id'] == incidentId);
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Обращение успешно удалено')),
        );
      } else {
        final data = jsonDecode(response.body);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось удалить: ${data['detail'] ?? 'Ошибка прав'}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка соединения: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Лента обращений')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Center(child: Text(_errorMessage, style: const TextStyle(color: Colors.red)))
              : _incidents.isEmpty
                  ? const Center(child: Text('Список обращений пуст'))
                  : ListView.builder(
                      itemCount: _incidents.length,
                      itemBuilder: (context, index) {
                        final inc = _incidents[index];
                        final bool isMyIncident = inc['student_id'] == widget.currentUserId;

                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          color: isMyIncident ? Colors.deepPurple[50] : null,
                          elevation: isMyIncident ? 4 : 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: isMyIncident
                                ? const BorderSide(color: Colors.deepPurple, width: 1.5)
                                : BorderSide.none,
                          ),
                          child: ListTile(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => IncidentDetailScreen(
                                    incident: inc,
                                    userRole: widget.userRole,
                                  ),
                                ),
                              );
                            },
                            leading: Icon(
                              inc['type'] == 'Жалоба' ? Icons.report_problem : Icons.lightbulb,
                              color: inc['type'] == 'Жалоба' ? Colors.red : Colors.blue,
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    inc['title'] ?? 'Без заголовка',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text('Категория: ${inc['category']}\nСтатус: ${inc['status']}'),
                                if (isMyIncident)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 4),
                                    child: Text(
                                      '★ Ваше обращение',
                                      style: TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                  ),
                              ],
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.grey),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Удаление'),
                                    content: const Text('Вы действительно хотите удалить это обращение?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(ctx);
                                          _deleteIncident(inc['id']);
                                        },
                                        child: const Text('Удалить', style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}

// ==================== ЭКРАН ДЕТАЛЬНОГО ПРОСМОТРА ====================
class IncidentDetailScreen extends StatelessWidget {
  final Map<String, dynamic> incident;
  final String userRole;

  const IncidentDetailScreen({
    super.key,
    required this.incident,
    required this.userRole,
  });

  @override
  Widget build(BuildContext context) {
    final bool isStaff = userRole == 'admin' || userRole == 'employee';

    return Scaffold(
      appBar: AppBar(
        title: Text(incident['title'] ?? 'Детали обращения'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isStaff) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Информация для проверяющего:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.brown)),
                    const SizedBox(height: 4),
                    Text('ID автора (студента): ${incident['student_id']}'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            const Text('Тип обращения:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            Text(incident['type'] ?? '', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 12),

            const Text('Категория:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            Text(incident['category'] ?? 'Не указана', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 12),

            const Text('Текущий статус:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 4),
            Chip(
              label: Text(incident['status'] ?? 'Новое'),
              backgroundColor: Colors.deepPurple[100],
            ),
            const SizedBox(height: 16),

            const Text('Подробная проблема / описание:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Text(
                incident['description'] ?? 'Описание отсутствует',
                style: const TextStyle(fontSize: 16, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== 4. ЭКРАН СОЗДАНИЯ ОБРАЩЕНИЯ (С ФОТО) ====================
class CreateIncidentScreen extends StatefulWidget {
  final int studentId;
  const CreateIncidentScreen({super.key, required this.studentId});

  @override
  State<CreateIncidentScreen> createState() => _CreateIncidentScreenState();
}

class _CreateIncidentScreenState extends State<CreateIncidentScreen> {
  String _type = 'Жалоба';
  String _category = 'оборудование';
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  String _statusMessage = '';
  bool _isSending = false;

  // Переменная для хранения выбранного изображения
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();

  // Функция для выбора изображения (из камеры или галереи)
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 85, // Сжатие изображения (0-100)
      );

      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка выбора фото: $e')),
      );
    }
  }

  // Функция отправки (включая логику отправки файла, если доделать бэкенд)
  Future<void> _submitIncident() async {
    if (_titleController.text.trim().length < 5 || _descController.text.trim().length < 20) {
       setState(() => _statusMessage = 'Заполните заголовок (мин.5) и описание (мин.20)');
       return;
    }

    setState(() {
      _isSending = true;
      _statusMessage = '';
    });

    try {
      // ПЕРСПЕКТИВА: Отправка файла требует multipart/form-data на бэкенде
      // Сейчас отправляем только JSON, файл пока просто висит в UI
      final response = await http.post(
        Uri.parse('$baseUrl/incidents'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'type': _type,
          'category': _category,
          'title': _titleController.text.trim(),
          'description': _descController.text.trim(),
          'student_id': widget.studentId,
          // 'image_path': _selectedImage != null ? 'path/on/server' : null, // Добавить после доработки бэкенда
        }),
      );

      if (response.statusCode == 201) {
        setState(() {
          _statusMessage = 'Обращение успешно создано!';
          _titleController.clear();
          _descController.clear();
          _selectedImage = null; // Очистить фото после отправки
        });
      } else {
        final data = jsonDecode(response.body);
        setState(() {
          _statusMessage = 'Ошибка: ${data['detail'] ?? 'Не удалось создать'}';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Ошибка соединения: $e';
      });
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Новое обращение')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              value: _type,
              items: const [
                DropdownMenuItem(value: 'Жалоба', child: Text('Жалоба')),
                DropdownMenuItem(value: 'Предложение', child: Text('Предложение')),
              ],
              onChanged: (val) => setState(() => _type = val!),
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
              onChanged: (val) => setState(() => _category = val!),
              decoration: const InputDecoration(labelText: 'Категория', prefixIcon: Icon(Icons.folder)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Заголовок (мин. 5 символов)', prefixIcon: Icon(Icons.title)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(
                labelText: 'Описание (минимум 20 символов!)',
                prefixIcon: Icon(Icons.description),
                helperText: 'Опишите проблему подробно',
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 16),

            // БЛОК ВЫБОРА ИЗОБРАЖЕНИЯ
            const Text('Доказательства (фото):', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                // Превью выбранного фото
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade400),
                  ),
                  child: _selectedImage == null
                      ? const Center(child: Icon(Icons.photo_camera, size: 40, color: Colors.grey))
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(_selectedImage!, fit: BoxFit.cover),
                        ),
                ),
                const SizedBox(width: 16),
                // Кнопки выбора
                Expanded(
                  child: Column(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _pickImage(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Сделать фото'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[50], foregroundColor: Colors.blue[900], minimumSize: const Size(double.infinity, 40)),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => _pickImage(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Выбрать из галереи'),
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.grey), minimumSize: const Size(double.infinity, 40)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_selectedImage != null)
               TextButton(
                 onPressed: () => setState(() => _selectedImage = null),
                 child: const Text('Удалить фото', style: TextStyle(color: Colors.red)),
               ),

            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _isSending ? null : _submitIncident,
              icon: const Icon(Icons.send),
              label: const Text('Отправить обращение'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(12)),
            ),
            const SizedBox(height: 16),
            Text(_statusMessage, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: _statusMessage.contains('успешно') ? Colors.green : Colors.red)),
          ],
        ),
      ),
    );
  }
}