import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../api.dart';
import '../state.dart';
import '../ui.dart';
import 'announcements.dart';
import 'committees.dart';
import 'inbox.dart';
import 'meetings.dart';
import 'profile.dart';
import 'tasks.dart';

/// App-bar actions on every tab: inbox (with unread count) and your profile.
List<Widget> appBarActions(BuildContext context) {
  final app = AppScope.of(context);
  final name = (app.me['name'] as String?) ?? '?';
  return [
    IconButton(
      tooltip: 'Inbox',
      icon: CountBadge(app.count('notifications'), child: const Icon(Icons.notifications_none_rounded)),
      onPressed: () => push(context, const InboxScreen()),
    ),
    Padding(
      padding: const EdgeInsets.only(right: 12, left: 2),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => push(context, const ProfileScreen()),
        child: Hero(tag: 'me-avatar', child: Initials(name, radius: 17)),
      ),
    ),
  ];
}

/// "Create" sheet for leaders: task, announcement or meeting.
Future<void> openCreate(BuildContext context) async {
  final r = await showActions(
    context,
    title: 'Create',
    actions: const [
      PickOption('task', 'Task', subtitle: 'Assign work to a committee or people', icon: Icons.task_alt_rounded),
      PickOption('announcement', 'Announcement', subtitle: 'Tell everyone, committees or people', icon: Icons.campaign_rounded),
      PickOption('meeting', 'Meeting', subtitle: 'Call a committee or general meeting', icon: Icons.event_rounded),
    ],
  );
  if (!context.mounted) return;
  switch (r) {
    case 'task':
      openNewTask(context);
    case 'announcement':
      openNewAnnouncement(context);
    case 'meeting':
      openNewMeeting(context);
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          children: [
            const BrandMark(size: 30),
            const SizedBox(width: 10),
            Flexible(child: Text(app.shortName, overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: appBarActions(context),
      ),
      floatingActionButton: app.canLead
          ? FloatingActionButton.extended(
              onPressed: () => openCreate(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create'),
            )
          : null,
      body: Loader(
        skeletonRows: 4,
        load: () => app.api!.get('home'),
        builder: (context, d, reload) {
          WidgetsBinding.instance.addPostFrameCallback((_) => app.setCountsQuietly(d['counts']));
          return _HomeBody(d: d, reload: reload);
        },
      ),
    );
  }
}

extension on AppState {
  void setCountsQuietly(Object? c) {
    if (c is Json && c.toString() != counts.toString()) setCounts(c);
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody({required this.d, required this.reload});
  final Json d;
  final Future<void> Function() reload;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final stats = d['stats'] as Json;
    final tasks = (d['my_tasks'] as List).cast<Json>();
    final anns = (d['announcements'] as List).cast<Json>();
    final meetings = (d['meetings'] as List).cast<Json>();
    final overview = (d['overview'] as List).cast<Json>();
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';
    var i = 0;

    return RefreshList(
      onRefresh: reload,
      children: [
        Appear(
          index: i++,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting, ${d['name']}',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.4),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('EEEE, d MMMM').format(DateTime.parse(d['today'] as String)),
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        Appear(index: i++, child: _Hero(stats: stats)),
        if (anns.isNotEmpty) ...[
          SectionTitle('Announcements', trailing: SeeAll(onTap: () => push(context, const AnnouncementsScreen(standalone: true)))),
          for (final a in anns)
            Appear(
              index: i++,
              child: AnnouncementCard(a, compact: true, onTap: () => push(context, AnnouncementDetailScreen(id: a['id'] as int))),
            ),
        ],
        if (meetings.isNotEmpty) ...[
          const SectionTitle('Coming up'),
          Appear(
            index: i++,
            child: ListCard(
              children: [
                for (final m in meetings)
                  MeetingTile(m, onTap: () => push(context, MeetingDetailScreen(id: m['id'] as int))),
              ],
            ),
          ),
        ],
        SectionTitle('My tasks', trailing: tasks.isEmpty ? null : SeeAll(onTap: () => push(context, const TasksScreen(initialScope: 'mine', standalone: true)))),
        Appear(
          index: i++,
          child: tasks.isEmpty
              ? Card(
                  margin: EdgeInsets.zero,
                  child: EmptyView('Nothing assigned to you right now.', icon: Icons.task_alt_rounded),
                )
              : ListCard(
                  children: [
                    for (final t in tasks) TaskTile(t, onTap: () => push(context, TaskDetailScreen(id: t['id'] as int))),
                  ],
                ),
        ),
        if (overview.isNotEmpty) ...[
          SectionTitle(app.isCore ? 'Committees at a glance' : 'Your committees'),
          for (final c in overview)
            Appear(index: i++, child: _CommitteeGlance(c: c)),
        ],
      ],
    );
  }
}

/// The gradient card with four live numbers.
class _Hero extends StatelessWidget {
  const _Hero({required this.stats});
  final Json stats;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget stat(String label, int value, IconData icon, {bool warn = false, VoidCallback? onTap}) => Expanded(
      child: Pressable(
        onTap: onTap,
        borderRadius: 16,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Column(
            children: [
              Icon(icon, size: 20, color: warn && value > 0 ? const Color(0xFFFFC46B) : Colors.white70),
              const SizedBox(height: 6),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: value.toDouble()),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => Text(
                  '${v.round()}',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                    color: warn && value > 0 ? const Color(0xFFFFC46B) : Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? brandGradientDark
              : brandGradient,
        ),
        boxShadow: [BoxShadow(color: brand.withValues(alpha: dark ? .15 : .3), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: Row(
        children: [
          stat('My tasks', stats['my_open'] as int, Icons.task_alt_rounded,
              onTap: () => push(context, const TasksScreen(initialScope: 'mine', standalone: true))),
          stat('Overdue', stats['overdue'] as int, Icons.schedule_rounded, warn: true,
              onTap: () => push(context, const TasksScreen(initialScope: 'all', standalone: true))),
          stat('Unread', stats['unread'] as int, Icons.campaign_rounded, warn: true,
              onTap: () => push(context, const AnnouncementsScreen(standalone: true))),
          stat('This week', stats['meetings'] as int, Icons.event_rounded,
              onTap: () => push(context, const MeetingsScreen(standalone: true))),
        ],
      ),
    );
  }
}

class _CommitteeGlance extends StatelessWidget {
  const _CommitteeGlance({required this.c});
  final Json c;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = colorOf(context, c);
    final open = c['open'] as int;
    final overdue = c['overdue'] as int;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Pressable(
        borderRadius: 18,
        onTap: () => push(context, CommitteeDetailScreen(id: c['id'] as int)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(13)),
                child: Icon(c['is_core'] == true ? Icons.star_rounded : Icons.groups_rounded, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c['name'] as String, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
                    const SizedBox(height: 2),
                    Text(
                      '${c['member_count']} members · $open open',
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (overdue > 0) Pill('$overdue overdue', tone: 'red') else if (open == 0) const Pill('All clear', tone: 'green'),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: cs.outline),
            ],
          ),
        ),
      ),
    );
  }
}
