import 'package:flutter/material.dart';

import '../theme.dart';

// Точка, которая мягко «дышит», если pulse = true
class PulseDot extends StatefulWidget {
  final Color color;
  final bool pulse;
  const PulseDot({super.key, required this.color, this.pulse = false});

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: widget.pulse
                ? [BoxShadow(color: widget.color.withAlpha((60 + 140 * _c.value).round()), blurRadius: 3 + 7 * _c.value, spreadRadius: _c.value)]
                : null,
          ),
        ),
      );
}

// Статус цветной «таблеткой»; «Новое» и «В работе» по умолчанию мигают
class StatusPill extends StatelessWidget {
  final String status;
  const StatusPill(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withAlpha(36),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withAlpha(100)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PulseDot(color: c, pulse: status == 'Новое' || status == 'В работе'),
          const SizedBox(width: 6),
          Text(status, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c)),
        ],
      ),
    );
  }
}
