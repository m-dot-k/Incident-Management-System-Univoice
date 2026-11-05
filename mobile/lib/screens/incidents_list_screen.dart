import 'package:flutter/material.dart';

import '../models/incident.dart';
import '../models/user.dart';
import '../services/api.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../utils/ui.dart';
import '../widgets/fade_in.dart';
import '../widgets/home_scope.dart';
import '../widgets/net_image.dart';
import '../widgets/status_pill.dart';
import '../widgets/status_text.dart';
import 'incident_detail_screen.dart';

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
    final r = await Api.get('/incidents');
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
        ? await Api.delete('/admin/incidents/${inc.id}', {'reason': reason ?? ''})
        : await Api.delete('/incidents/${inc.id}');
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
                child: SizedBox(width: 52, height: 52, child: NetImage(inc.photos.first)),
              ),
        title: Text(inc.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('${inc.category} · ${fmtDate(inc.createdAt)}', style: const TextStyle(fontSize: 13, color: kMuted)),
            const SizedBox(height: 8),
            StatusPill(inc.status),
            if (inc.isMine)
              const Padding(
                padding: EdgeInsets.only(top: 6),
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
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            StatusText(_error),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                setState(() => _loading = true);
                _load();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
            ),
          ]),
        ),
      ]);
    } else if (shown.isEmpty) {
      body = ListView(children: const [Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Список обращений пуст')))]);
    } else {
      body = ListView.builder(itemCount: shown.length, itemBuilder: (_, i) => FadeIn(index: i, child: _card(shown[i])));
    }
    return Scaffold(
      appBar: AppBar(leading: HomeScope.backButton(context), title: const Text('Лента обращений')),
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
                      avatar: f == null ? null : Icon(Icons.circle, size: 10, color: statusColor(f)),
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
