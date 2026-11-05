import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/incident.dart';
import '../models/user.dart';
import '../services/api.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../utils/ui.dart';
import '../widgets/fade_in.dart';
import '../widgets/net_image.dart';
import '../widgets/status_pill.dart';

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
      try {
        final updated = Incident.fromJson(Map<String, dynamic>.from(r.data), user.id);
        setState(() {
          incident = updated;
          _busy = false;
        });
        snack(context, okText);
        return;
      } catch (_) {}
    }
    setState(() => _busy = false);
    snack(context, r.ok ? 'Ошибка. Не удалось обновить обращение' : r.error('Не удалось выполнить действие'));
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
    setState(() => _busy = true);
    final r = await Api.get('/employees');
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok || r.data is! List) {
      snack(context, r.error('Не удалось загрузить сотрудников'));
      return;
    }
    final employees = [for (final e in r.data as List) if (e is Map && e['id'] is int) e];
    if (employees.isEmpty) {
      snack(context, 'Нет активных сотрудников');
      return;
    }
    final id = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Назначить сотрудника'),
        children: [
          for (final e in employees)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, e['id'] as int),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline, color: kAccent),
                title: Text('${e['display_name'] ?? 'Сотрудник'}'),
                subtitle: Text('${e['email'] ?? ''}', style: const TextStyle(color: kMuted)),
              ),
            ),
        ],
      ),
    );
    if (id != null && mounted) _status('Назначено', employeeId: id);
  }

  Future<void> _reopen() async {
    final v = await _ask('Вернуть на доработку', 'Что не так? (причина)', min: 3);
    if (v != null) _status('Новое', reason: v);
  }

  Future<void> _finish() async {
    final c = TextEditingController();
    File? photo;
    String pickErr = '';
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSurface,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          Future<void> pick(ImageSource src) async {
            try {
              final x = await ImagePicker().pickImage(source: src, imageQuality: 85, maxWidth: 1600, maxHeight: 1600);
              if (x != null) {
                set(() {
                  photo = File(x.path);
                  pickErr = '';
                });
              }
            } catch (e) {
              // Ошибку показываем прямо в окне: snackbar оказался бы под ним
              if (ctx.mounted) set(() => pickErr = pickErrorText(e));
            }
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
                if (pickErr.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(pickErr, style: const TextStyle(color: Color(0xFFFF7A8A), fontSize: 13)),
                  ),
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
      {if (c.text.trim().isNotEmpty) 'comment': c.text.trim()},
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
        ? await Api.delete('/admin/incidents/${incident.id}', {'reason': reason})
        : await Api.delete('/incidents/${incident.id}');
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
    const pad = EdgeInsets.symmetric(vertical: 16);
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
            onTap: () => openPhoto(context, items[i].url),
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
                      NetImage(items[i].url),
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
              Align(alignment: Alignment.centerLeft, child: StatusPill(incident.status)),
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
