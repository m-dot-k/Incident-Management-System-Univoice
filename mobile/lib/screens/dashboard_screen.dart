import 'package:flutter/material.dart';

import '../models/incident.dart';
import '../models/user.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/fade_in.dart';
import 'incident_detail_screen.dart';

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
  String _error = '';

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
        final l = (r.data as List).map((j) => Incident.fromJson(Map<String, dynamic>.from(j), widget.user.id)).toList();
        setState(() {
          _items = l;
          _error = '';
        });
        return;
      } catch (_) {}
    }
    setState(() => _error = r.ok ? 'Ошибка. Не удалось прочитать ответ сервера' : r.error('Не удалось загрузить обращения'));
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
                                            ? (_error.isNotEmpty ? _error : 'Загружаем обращения…')
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
