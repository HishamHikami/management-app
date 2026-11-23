import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'screens/announcements.dart';
import 'screens/committees.dart';
import 'screens/home.dart';
import 'screens/login.dart';
import 'screens/meetings.dart';
import 'screens/tasks.dart';
import 'state.dart';
import 'ui.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final state = AppState()..init();
  runApp(AppScope(state: state, child: const UnitApp()));
}

ThemeData _theme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: brand, brightness: b);
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: b);
  final dark = b == Brightness.dark;
  final bg = dark ? const Color(0xFF0B1414) : const Color(0xFFF3F6F6);
  final card = dark ? const Color(0xFF122020) : Colors.white;
  final line = dark ? const Color(0xFF1F3232) : const Color(0xFFE2E9E9);
  return base.copyWith(
    scaffoldBackgroundColor: bg,
    cardColor: card,
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 1,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -.2,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: line)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: dark ? const Color(0xFF2A3F3F) : const Color(0xFFD8E0E0)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 70,
      backgroundColor: card,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStatePropertyAll(
        base.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 0),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()},
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      extendedTextStyle: const TextStyle(fontWeight: FontWeight.w700),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: dark ? const Color(0xFF3A4F4F) : const Color(0xFFCAD4D4),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      clipBehavior: Clip.antiAlias,
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      dayShape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      yearShape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      todayBorder: BorderSide(color: scheme.primary, width: 1.5),
      dayStyle: const TextStyle(fontWeight: FontWeight.w600),
      weekdayStyle: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.transparent,
      selectedColor: scheme.primaryContainer,
      side: WidgetStateBorderSide.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? BorderSide(color: scheme.primaryContainer)
            : BorderSide(color: scheme.outlineVariant),
      ),
      shape: const StadiumBorder(),
      labelStyle: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
    ),
    snackBarTheme: SnackBarThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: DividerThemeData(color: line),
  );
}

class UnitApp extends StatelessWidget {
  const UnitApp({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return MaterialApp(
      title: app.shortName,
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: app.messages,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 420),
        switchInCurve: Curves.easeOutCubic,
        transitionBuilder: (child, a) => FadeTransition(
          opacity: a,
          child: ScaleTransition(scale: Tween(begin: .98, end: 1.0).animate(a), child: child),
        ),
        child: app.loading
            ? const _Splash(key: ValueKey('splash'))
            : app.api == null
            ? const LoginScreen(key: ValueKey('login'))
            : const Shell(key: ValueKey('shell')),
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: BrandMark(size: 76)));
}

/// Bottom tabs. Each tab has its own navigation stack, so the tab bar stays
/// visible on detail pages and every tab remembers where you were.
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;
  final _keys = List.generate(5, (_) => GlobalKey<NavigatorState>());

  Widget _root(int i) => switch (i) {
    0 => const HomeScreen(),
    1 => const TasksScreen(),
    2 => const AnnouncementsScreen(),
    3 => const MeetingsScreen(),
    _ => const CommitteesScreen(),
  };

  void _select(int i) {
    HapticFeedback.selectionClick();
    if (i == _index) {
      _keys[i].currentState?.popUntil((r) => r.isFirst);
    } else {
      setState(() => _index = i);
    }
  }

  void _openTarget(OpenTarget t) {
    final (tab, page) = switch (t.kind) {
      'task' => (1, TaskDetailScreen(id: t.id) as Widget),
      'announcement' => (2, AnnouncementDetailScreen(id: t.id)),
      'meeting' => (3, MeetingDetailScreen(id: t.id)),
      _ => (0, null),
    };
    setState(() => _index = tab);
    if (page != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _keys[tab].currentState?.push(MaterialPageRoute(builder: (_) => page));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (app.openTarget != null) {
      final t = app.takeOpenTarget()!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _openTarget(t));
    }
    final news = app.count('announcements');
    final rsvp = app.count('rsvp');
    final destinations = [
      const NavigationDestination(icon: Icon(Icons.space_dashboard_outlined), selectedIcon: Icon(Icons.space_dashboard_rounded), label: 'Home'),
      const NavigationDestination(icon: Icon(Icons.task_alt_rounded), selectedIcon: Icon(Icons.task_alt_rounded), label: 'Tasks'),
      NavigationDestination(
        icon: CountBadge(news, child: const Icon(Icons.campaign_outlined)),
        selectedIcon: CountBadge(news, child: const Icon(Icons.campaign_rounded)),
        label: 'News',
      ),
      NavigationDestination(
        icon: CountBadge(rsvp, child: const Icon(Icons.event_outlined)),
        selectedIcon: CountBadge(rsvp, child: const Icon(Icons.event_rounded)),
        label: 'Meetings',
      ),
      const NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups_rounded), label: 'Committees'),
    ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final nav = _keys[_index].currentState;
        if (nav != null && nav.canPop()) {
          nav.pop();
        } else if (_index != 0) {
          setState(() => _index = 0);
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            for (var i = 0; i < 5; i++)
              _FadeThroughTab(
                active: i == _index,
                child: Navigator(
                  key: _keys[i],
                  onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => _root(i)),
                ),
              ),
          ],
        ),
        // Tab labels stay on one line even with a large system font size.
        bottomNavigationBar: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.1),
          ),
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _select,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: destinations,
          ),
        ),
      ),
    );
  }
}

/// Keeps a tab alive but hidden when not selected; fades and lifts it in when selected.
class _FadeThroughTab extends StatefulWidget {
  const _FadeThroughTab({required this.active, required this.child});
  final bool active;
  final Widget child;
  @override
  State<_FadeThroughTab> createState() => _FadeThroughTabState();
}

class _FadeThroughTabState extends State<_FadeThroughTab> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: widget.active ? 1 : 0,
  );
  late final Animation<double> _fade = CurvedAnimation(parent: _c, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween(begin: const Offset(0, .015), end: Offset.zero)
      .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));
  late final Animation<double> _scale = Tween(begin: .985, end: 1.0)
      .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));

  @override
  void didUpdateWidget(_FadeThroughTab old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _c.forward(from: 0);
    if (!widget.active) _c.value = 0;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Offstage(
      offstage: !widget.active,
      child: TickerMode(
        enabled: widget.active,
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: ScaleTransition(scale: _scale, child: widget.child),
          ),
        ),
      ),
    );
  }
}
