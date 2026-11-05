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
