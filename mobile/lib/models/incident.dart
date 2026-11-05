const kStatuses = ['Новое', 'Назначено', 'В работе', 'Решено', 'Закрыто'];

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
