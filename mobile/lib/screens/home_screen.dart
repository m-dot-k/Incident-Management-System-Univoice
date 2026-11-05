import 'package:flutter/material.dart';

import '../models/user.dart';
import '../theme.dart';
import '../widgets/home_scope.dart';
import 'create_incident_screen.dart';
import 'dashboard_screen.dart';
import 'incidents_list_screen.dart';
import 'profile_screen.dart';

// Открыть главный экран (заменяет всю историю переходов)
void openHome(BuildContext context, User user) => Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => HomeScreen(user: user)),
      (_) => false,
    );

class HomeScreen extends StatefulWidget {
  final User user;
  const HomeScreen({super.key, required this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _Tab { home, feed, create, profile }

class _HomeScreenState extends State<HomeScreen> {
  _Tab _tab = _Tab.home;
  String? _filter;
  // Счётчики пересоздают главную и ленту при каждом переходе, чтобы данные обновлялись,
  // а форма создания живёт в IndexedStack и не теряет введённый текст
  int _homeGen = 0, _feedGen = 0;

  // Создавать обращения могут только студенты
  late final List<_Tab> _tabs = [
    _Tab.home,
    _Tab.feed,
    if (widget.user.role == 'student') _Tab.create,
    _Tab.profile,
  ];

  void _go(_Tab tab, {String? filter}) => setState(() {
        _tab = tab;
        _filter = filter;
        if (tab == _Tab.home) _homeGen++;
        if (tab == _Tab.feed) _feedGen++;
      });

  Widget _page(_Tab t) {
    final u = widget.user;
    return switch (t) {
      _Tab.home => DashboardTab(
          key: ValueKey('home$_homeGen'),
          user: u,
          onOpenFeed: (f) => _go(_Tab.feed, filter: f),
          onCreate: _tabs.contains(_Tab.create) ? () => _go(_Tab.create) : () => _go(_Tab.feed),
        ),
      _Tab.feed => IncidentsListScreen(key: ValueKey('feed$_feedGen'), user: u, initialFilter: _filter),
      _Tab.create => CreateIncidentScreen(user: u),
      _Tab.profile => ProfileTab(user: u),
    };
  }

  @override
  Widget build(BuildContext context) {
    final onHome = _tab == _Tab.home;
    return HomeScope(
      onHome: onHome,
      goHome: () => _go(_Tab.home),
      // Жест/кнопка «назад» на вкладке возвращает на «Главную», а не закрывает приложение
      child: PopScope(
        canPop: onHome,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _go(_Tab.home);
        },
        child: Scaffold(
          body: IndexedStack(index: _tabs.indexOf(_tab), children: [for (final t in _tabs) _page(t)]),
          bottomNavigationBar: _NavBar(tabs: _tabs, current: _tab, onTap: (t) => _go(t)),
        ),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  final List<_Tab> tabs;
  final _Tab current;
  final ValueChanged<_Tab> onTap;
  const _NavBar({required this.tabs, required this.current, required this.onTap});

  static const _off = {
    _Tab.home: Icons.home_outlined,
    _Tab.feed: Icons.list_alt_outlined,
    _Tab.create: Icons.add_circle_outline,
    _Tab.profile: Icons.person_outline,
  };
  static const _on = {_Tab.home: Icons.home, _Tab.feed: Icons.list_alt, _Tab.create: Icons.add_circle, _Tab.profile: Icons.person};
  static const _names = {_Tab.home: 'Главная', _Tab.feed: 'Лента', _Tab.create: 'Создать', _Tab.profile: 'Профиль'};

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(color: kSurface, border: Border(top: BorderSide(color: kBorder))),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                for (final t in tabs)
                  Expanded(
                    child: InkResponse(
                      onTap: () => onTap(t),
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                          decoration: BoxDecoration(
                            color: current == t ? const Color(0x269D8CFF) : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(current == t ? _on[t] : _off[t],
                              semanticLabel: _names[t], color: current == t ? kAccent : kMuted),
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
