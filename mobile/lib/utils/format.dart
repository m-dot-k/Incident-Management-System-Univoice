String fmtDate(DateTime? d) {
  if (d == null) return '—';
  final l = d.toLocal();
  String t(int n) => n.toString().padLeft(2, '0');
  return '${t(l.day)}.${t(l.month)}.${l.year} ${t(l.hour)}:${t(l.minute)}';
}
