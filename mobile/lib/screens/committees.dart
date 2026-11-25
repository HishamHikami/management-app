import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../state.dart';
import '../ui.dart';
import 'announcements.dart';
import 'home.dart';
import 'meetings.dart';
import 'tasks.dart';

class CommitteesScreen extends StatefulWidget {
  const CommitteesScreen({super.key});
  @override
  State<CommitteesScreen> createState() => _CommitteesScreenState();
}

class _CommitteesScreenState extends State<CommitteesScreen> {
  String _tab = 'committees';
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final people = _tab == 'people';
    final fab = people
        ? (app.canManagePeople
              ? FloatingActionButton.extended(
                  heroTag: 'people-fab',
                  onPressed: () => push(context, const PersonEditor()),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Add person'),
                )
              : null)
        : (app.isCore
              ? FloatingActionButton(
                  heroTag: 'com-fab',
                  tooltip: 'New wing',
                  onPressed: () => push(context, const CommitteeEditor()),
                  child: const Icon(Icons.add_rounded),
                )
              : null);
    return Scaffold(
      appBar: AppBar(title: const Text('Wings'), actions: appBarActions(context)),
      floatingActionButton: AnimatedSwitcher(duration: const Duration(milliseconds: 200), child: fab),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Segments<String>(
              items: [('committees', 'Wings'), ('people', 'People')],
              value: _tab,
              onChanged: (v) => setState(() => _tab = v),
            ),
          ),
          if (people)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: TextField(
                onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'Search people',
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(99)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(99),
                    borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              child: people ? _PeopleList(key: const ValueKey('p'), q: _q) : const _CommitteeGrid(key: ValueKey('c')),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommitteeGrid extends StatelessWidget {
  const _CommitteeGrid({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Loader(
      load: () => app.api!.get('committees'),
      builder: (context, d, reload) {
        final list = (d['committees'] as List).cast<Json>();
        final core = list.where((c) => c['is_core'] == true).toList();
        final rest = list.where((c) => c['is_core'] != true).toList();
        if (list.isEmpty) {
          return const EmptyView('No wings yet.', icon: Icons.groups_outlined);
        }
        return RefreshList(
          onRefresh: reload,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            for (final c in core) Appear(index: 0, child: _CoreCard(c: c)),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, box) {
                final cols = box.maxWidth > 560 ? 3 : 2;
                final w = (box.maxWidth - 10 * (cols - 1)) / cols;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (var i = 0; i < rest.length; i++)
                      SizedBox(width: w, child: Appear(index: i + 1, child: _CommitteeCard(c: rest[i]))),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _CoreCard extends StatelessWidget {
  const _CoreCard({required this.c});
  final Json c;
  @override
  Widget build(BuildContext context) {
    final heads = (c['heads'] as List).cast<Json>();
    return Pressable(
      borderRadius: 22,
      onTap: () => push(context, CommitteeDetailScreen(id: c['id'] as int)),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: brandGradient,
          ),
          boxShadow: [BoxShadow(color: brand.withValues(alpha: .28), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.star_rounded, color: Color(0xFFFFD27A)),
                const SizedBox(width: 6),
                const Text('CORE COMMITTEE', style: TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1)),
                const Spacer(),
                if (c['my_role'] != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .18), borderRadius: BorderRadius.circular(99)),
                    child: const Text('You\'re in it', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(c['name'] as String, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            if ((c['description'] as String).isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(c['description'] as String, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70)),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Text('${c['member_count']} members', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                const Text('  ·  ', style: TextStyle(color: Colors.white54)),
                Text('${c['open']} open tasks', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                const Spacer(),
                if (heads.isNotEmpty)
                  Text('Led by ${heads.first['name'].toString().split(' ').first}', style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CommitteeCard extends StatelessWidget {
  const _CommitteeCard({required this.c});
  final Json c;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = colorOf(context, c);
    final heads = (c['heads'] as List).cast<Json>();
    final overdue = c['overdue'] as int;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Pressable(
        borderRadius: 18,
        onTap: () => push(context, CommitteeDetailScreen(id: c['id'] as int)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.groups_rounded, color: color, size: 21),
                  ),
                  const Spacer(),
                  if (c['my_role'] != null && c['my_role'] != 'member' && c['my_role'] != '')
                    Pill(c['my_role'] as String, tone: 'brand')
                  else if (c['my_role'] != null)
                    Icon(Icons.check_circle_rounded, size: 18, color: color),
                ],
              ),
              const SizedBox(height: 12),
              Text(c['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
              const SizedBox(height: 2),
              Text(
                heads.isEmpty ? 'No head yet' : heads.map((h) => h['name'].toString().split(' ').first).join(', '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.person_outline_rounded, size: 15, color: cs.onSurfaceVariant),
                  Text(' ${c['member_count']}', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 10),
                  Icon(Icons.task_alt_rounded, size: 15, color: overdue > 0 ? Tones.red(context) : cs.onSurfaceVariant),
                  Text(' ${c['open']}',
                      style: TextStyle(fontSize: 12.5, color: overdue > 0 ? Tones.red(context) : cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String statusLabel(String? s) => switch (s) {
  'active' => 'Active',
  'invited' => 'Invite sent',
  'not_invited' => 'Not invited',
  'inactive' => 'Inactive',
  _ => '',
};

String statusTone(String? s) => switch (s) {
  'active' => 'green',
  'invited' => 'amber',
  'not_invited' => 'ghost',
  _ => 'red',
};

class _PeopleList extends StatefulWidget {
  const _PeopleList({super.key, required this.q});
  final String q;
  @override
  State<_PeopleList> createState() => _PeopleListState();
}

class _PeopleListState extends State<_PeopleList> {
  String _filter = 'all';
  String? _place;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final manage = app.canManagePeople;
    return Loader(
      load: () => app.api!.get('members', query: {'all': manage ? '1' : ''}),
      builder: (context, d, reload) {
        final all = (d['members'] as List).cast<Json>();
        final places = all.map((m) => (m['unit_place'] as String?) ?? '').where((p) => p.isNotEmpty).toSet().toList()..sort();
        bool keep(Json m) {
          final q = widget.q;
          if (q.isNotEmpty &&
              !'${m['name']} ${m['title']} ${m['phone']} ${m['email']} ${m['unit_place']} ${(m['committees'] as List).map((c) => (c as Json)['name']).join(' ')}'
                  .toLowerCase()
                  .contains(q)) {
            return false;
          }
          if (_place != null && m['unit_place'] != _place) return false;
          return switch (_filter) {
            'executive' => m['member_type'] == 'executive',
            'member' => m['member_type'] != 'executive',
            'not_invited' => m['status'] == 'not_invited' || m['status'] == 'invited',
            'followup' => m['needs_followup'] == true,
            _ => true,
          };
        }

        final list = all.where(keep).toList();
        final execs = list.where((m) => m['member_type'] == 'executive').toList();
        final rest = list.where((m) => m['member_type'] != 'executive').toList();
        final filters = <(String, String)>[
          ('all', 'All · ${all.length}'),
          ('executive', 'Executives'),
          ('member', 'Members'),
          if (manage) ('not_invited', 'Not active yet'),
          if (manage) ('followup', 'Follow-up'),
        ];

        Widget row(Json m) => PersonTile(
          m,
          subtitle: [
            if ((m['title'] as String).isNotEmpty) m['title'] as String,
            ...(m['committees'] as List).map((c) {
              final pos = ((c as Json)['position'] as String?) ?? '';
              return pos.isEmpty || pos.toLowerCase() == 'member' ? c['name'] as String : '${c['name']} ($pos)';
            }),
            if ((m['unit_place'] as String?)?.isNotEmpty == true) m['unit_place'] as String,
          ].join(' · '),
          trailing: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (m['level'] == 'super')
                const Pill('Super admin', tone: 'brand')
              else if (m['level'] == 'admin')
                const Pill('Admin', tone: 'brand')
              else if (manage && m['status'] != 'active')
                Pill(statusLabel(m['status'] as String?), tone: statusTone(m['status'] as String?)),
              if (manage && m['needs_followup'] == true) ...[
                const SizedBox(height: 3),
                Icon(Icons.flag_rounded, size: 16, color: Tones.amber(context)),
              ],
            ],
          ),
          onTap: () => push(context, MemberDetailScreen(id: m['id'] as int)),
        );

        return Column(
          children: [
            ChipRow(children: [
              for (final f in filters)
                ChoiceChip(label: Text(f.$2), selected: _filter == f.$1, showCheckmark: false, onSelected: (_) => setState(() => _filter = f.$1)),
              if (places.isNotEmpty)
                ActionChip(
                  avatar: const Icon(Icons.place_outlined, size: 18),
                  label: Text(_place ?? 'All places'),
                  onPressed: () async {
                    final r = await showPicker<String?>(context, title: 'Unit place', selected: _place, groups: [
                      PickGroup([const PickOption<String?>(null, 'All places'), for (final p in places) PickOption<String?>(p, p)]),
                    ]);
                    if (r != null) setState(() => _place = r.value);
                  },
                ),
            ]),
            Expanded(
              child: RefreshList(
                onRefresh: reload,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                children: [
                  if (list.isEmpty) const EmptyView('Nobody found.', icon: Icons.person_search_outlined),
                  if (execs.isNotEmpty) ...[
                    SectionTitle('Executives · ${execs.length}'),
                    ListCard(children: [for (final m in execs) row(m)]),
                  ],
                  if (rest.isNotEmpty) ...[
                    SectionTitle('Members · ${rest.length}'),
                    ListCard(children: [for (final m in rest) row(m)]),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class CommitteeDetailScreen extends StatelessWidget {
  const CommitteeDetailScreen({super.key, required this.id});
  final int id;
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Loader(
      load: () => app.api!.get('committees/$id'),
      builder: (context, d, reload) => _CommitteePage(c: d['committee'] as Json, reload: reload),
    );
  }
}

class _CommitteePage extends StatelessWidget {
  const _CommitteePage({required this.c, required this.reload});
  final Json c;
  final Future<void> Function() reload;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final color = colorOf(context, c);
    final id = c['id'] as int;
    final members = (c['members'] as List).cast<Json>();
    final tasks = (c['tasks'] as List).cast<Json>();
    final meetings = (c['meetings'] as List).cast<Json>();
    final anns = (c['announcements'] as List).cast<Json>();
    final manage = c['can_manage'] == true;
    final lead = app.leadableIds.contains(id);

    Future<void> memberActions(Json m) async {
      final r = await showActions(
        context,
        title: m['name'] as String,
        actions: [
          const PickOption('view', 'View profile', icon: Icons.person_outline_rounded),
          if (manage) const PickOption('position', 'Set position in this wing', icon: Icons.badge_outlined),
          if (manage) const PickOption('remove', 'Remove from wing', icon: Icons.person_remove_outlined, danger: true),
        ],
      );
      if (!context.mounted || r == null) return;
      if (r == 'view') {
        push(context, MemberDetailScreen(id: m['id'] as int));
        return;
      }
      try {
        if (r == 'remove') {
          if (!await confirm(context, title: 'Remove ${m['name']}?', message: 'They leave ${c['name']}.', action: 'Remove', danger: true)) return;
          await app.api!.delete('committees/$id/members/${m['id']}');
        } else {
          final pos = await pickPosition(context, current: (m['position'] as String?) ?? '');
          if (pos == null) return;
          await app.api!.patch('committees/$id/members/${m['id']}', {'position': pos});
        }
        app.changed(boot: true);
      } catch (e) {
        if (context.mounted) showApiError(context, e);
      }
    }

    Future<void> addMembers() async {
      final have = members.map((m) => m['id'] as int).toSet();
      final r = await showMultiPicker<int>(
        context,
        title: 'Add to ${c['name']}',
        searchable: true,
        doneLabel: 'Add',
        groups: [
          PickGroup([
            for (final m in app.members.where((m) => !have.contains(m['id'])))
              PickOption(m['id'] as int, m['name'] as String, leading: Initials(m['name'] as String),
                  subtitle: (m['title'] as String?)?.isNotEmpty == true ? m['title'] as String : null),
          ]),
        ],
      );
      if (r == null || r.isEmpty || !context.mounted) return;
      try {
        await app.api!.post('committees/$id/members', {'members': r.toList()});
        app.changed(boot: true);
        if (context.mounted) toast(context, 'Added ${r.length}');
      } catch (e) {
        if (context.mounted) showApiError(context, e);
      }
    }

    Future<void> menu() async {
      final r = await showActions(
        context,
        title: c['name'] as String,
        actions: [
          const PickOption('edit', 'Edit wing', icon: Icons.edit_outlined),
          if (c['is_core'] != true) const PickOption('archive', 'Archive wing', icon: Icons.archive_outlined, danger: true),
        ],
      );
      if (!context.mounted) return;
      if (r == 'edit') push(context, CommitteeEditor(existing: c));
      if (r == 'archive' &&
          await confirm(context, title: 'Archive ${c['name']}?', message: 'It disappears from lists; its history is kept.', action: 'Archive', danger: true)) {
        try {
          await app.api!.delete('committees/$id');
          app.changed(boot: true);
          if (context.mounted) Navigator.pop(context);
        } catch (e) {
          if (context.mounted) showApiError(context, e);
        }
      }
    }

    var i = 0;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: reload,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            SliverAppBar.large(
              backgroundColor: Color.alphaBlend(color.withValues(alpha: .12), Theme.of(context).scaffoldBackgroundColor),
              title: Text(c['name'] as String),
              actions: [if (app.isCore) IconButton(icon: const Icon(Icons.more_vert_rounded), onPressed: menu)],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
              sliver: SliverList.list(
                children: [
                  if ((c['description'] as String).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
                      child: Text(c['description'] as String, style: TextStyle(color: cs.onSurfaceVariant, height: 1.4)),
                    ),
                  Appear(
                    index: i++,
                    child: Row(
                      children: [
                        _MiniStat(value: '${members.length}', label: 'Members', color: color),
                        const SizedBox(width: 10),
                        _MiniStat(value: '${c['open']}', label: 'Open tasks', color: color),
                        const SizedBox(width: 10),
                        _MiniStat(value: '${c['overdue']}', label: 'Overdue', color: (c['overdue'] as int) > 0 ? Tones.red(context) : color),
                      ],
                    ),
                  ),
                  if (lead) ...[
                    const SizedBox(height: 14),
                    Appear(
                      index: i++,
                      child: Row(
                        children: [
                          _QuickAction(icon: Icons.task_alt_rounded, label: 'Task', onTap: () => openNewTask(context, committeeId: id)),
                          _QuickAction(icon: Icons.campaign_rounded, label: 'Announce', onTap: () => openNewAnnouncement(context, committeeId: id)),
                          _QuickAction(icon: Icons.event_rounded, label: 'Meeting', onTap: () => openNewMeeting(context, committeeId: id)),
                        ],
                      ),
                    ),
                  ],
                  SectionTitle(
                    'Open tasks',
                    trailing: SeeAll(onTap: () => push(context, TasksScreen(standalone: true, initialScope: app.allWings('tasks') ? 'all' : 'team', committeeId: id))),
                  ),
                  Appear(
                    index: i++,
                    child: tasks.isEmpty
                        ? const Card(margin: EdgeInsets.zero, child: EmptyView('No open tasks.', icon: Icons.task_alt_rounded))
                        : ListCard(
                            children: [
                              for (final t in tasks.take(6))
                                TaskTile(t, hideCommittee: true, onTap: () => push(context, TaskDetailScreen(id: t['id'] as int))),
                            ],
                          ),
                  ),
                  if (meetings.isNotEmpty) ...[
                    const SectionTitle('Upcoming meetings'),
                    Appear(
                      index: i++,
                      child: ListCard(
                        children: [
                          for (final m in meetings) MeetingTile(m, onTap: () => push(context, MeetingDetailScreen(id: m['id'] as int))),
                        ],
                      ),
                    ),
                  ],
                  if (anns.isNotEmpty) ...[
                    const SectionTitle('Recent announcements'),
                    for (final a in anns)
                      Appear(
                        index: i++,
                        child: AnnouncementCard(a, compact: true, onTap: () => push(context, AnnouncementDetailScreen(id: a['id'] as int))),
                      ),
                  ],
                  SectionTitle(
                    'Members · ${members.length}',
                    trailing: manage ? SeeAll(label: 'Add', onTap: addMembers) : null,
                  ),
                  Appear(
                    index: i++,
                    child: members.isEmpty
                        ? const Card(margin: EdgeInsets.zero, child: EmptyView('No members yet.', icon: Icons.group_add_outlined))
                        : ListCard(
                            children: [
                              for (final m in members)
                                PersonTile(
                                  m,
                                  subtitle: [
                                    if ((m['position'] as String? ?? '').isNotEmpty) m['position'] as String,
                                    if ((m['title'] as String? ?? '').isNotEmpty) m['title'] as String,
                                  ].join(' · '),
                                  trailing: ((m['position'] as String?) ?? '').isNotEmpty && (m['position'] as String).toLowerCase() != 'member'
                                      ? Pill(m['position'] as String, tone: 'brand')
                                      : null,
                                  onTap: () => memberActions(m),
                                ),
                            ],
                          ),
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

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.value, required this.label, required this.color});
  final String value;
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    ),
  );
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: cs.primaryContainer.withValues(alpha: .6),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  Icon(icon, color: cs.onPrimaryContainer),
                  const SizedBox(height: 4),
                  Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: cs.onPrimaryContainer)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ======================================================================= committee editor

class CommitteeEditor extends StatefulWidget {
  const CommitteeEditor({super.key, this.existing});
  final Json? existing;
  @override
  State<CommitteeEditor> createState() => _CommitteeEditorState();
}

class _CommitteeEditorState extends State<CommitteeEditor> {
  late final _name = TextEditingController(text: widget.existing?['name'] as String?);
  late final _desc = TextEditingController(text: widget.existing?['description'] as String?);
  late String _color = (widget.existing?['color'] as String?) ?? 'blue';
  ApiException? _error;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final editing = widget.existing != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit wing' : 'New wing')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            controller: _name,
            autofocus: !editing,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: 'Name', errorText: fieldError(_error, 'name')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'What does it do? (optional)', alignLabelWithHint: true),
          ),
          const SizedBox(height: 18),
          Text('Colour', style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final c in ((app.boot?['choices'] as Json?)?['colors'] as List? ?? const []).cast<String>())
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _color = c);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: committeeColor(c, Theme.of(context).brightness),
                      shape: BoxShape.circle,
                      border: Border.all(color: _color == c ? Theme.of(context).colorScheme.onSurface : Colors.transparent, width: 3),
                    ),
                    child: _color == c ? const Icon(Icons.check_rounded, color: Colors.white) : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 28),
          BusyButton(
            label: editing ? 'Save' : 'Create wing',
            icon: Icons.check_rounded,
            onPressed: () async {
              setState(() => _error = null);
              final nav = Navigator.of(context);
              final body = {'name': _name.text, 'description': _desc.text, 'color': _color};
              try {
                final r = editing
                    ? await app.api!.patch('committees/${widget.existing!['id']}', body)
                    : await app.api!.post('committees', body);
                app.changed(boot: true);
                nav.pop();
                // The navigator outlives this page, so its context is still valid.
                // ignore: use_build_context_synchronously
                if (!editing) push(nav.context, CommitteeDetailScreen(id: (r['committee'] as Json)['id'] as int));
              } on ApiException catch (e) {
                setState(() => _error = e);
                if (context.mounted) showApiError(context, e);
              }
            },
          ),
        ],
      ),
    );
  }
}

// ======================================================================= people

class MemberDetailScreen extends StatelessWidget {
  const MemberDetailScreen({super.key, required this.id});
  final int id;
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Loader(
      load: () => app.api!.get('members/$id'),
      builder: (context, d, reload) => _MemberPage(m: d['member'] as Json, reload: reload),
    );
  }
}

String levelLabel(String? l) => switch (l) { 'super' => 'Super admin', 'admin' => 'Admin', _ => 'Member' };

class _MemberPage extends StatelessWidget {
  const _MemberPage({required this.m, required this.reload});
  final Json m;
  final Future<void> Function() reload;
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final committees = (m['committees'] as List).cast<Json>();
    final tasks = ((m['open_tasks'] as List?) ?? []).cast<Json>();
    final duties = ((m['responsibilities'] as List?) ?? []).cast<Json>();
    final manage = m['can_manage'] == true;
    final isMe = m['id'] == app.meId;
    final status = m['status'] as String?;
    final perms = ((m['permissions'] as Json?) ?? const {});

    Future<void> sendCode() async {
      try {
        final x = await app.api!.post('members/${m['id']}/invite');
        if (context.mounted) await showInviteCode(context, m, x['code'] as String, x['message'] as String);
        reload();
      } catch (e) {
        if (context.mounted) showApiError(context, e);
      }
    }

    Future<void> menu() async {
      final r = await showActions(
        context,
        title: m['name'] as String,
        actions: [
          const PickOption('edit', 'Edit details', icon: Icons.edit_outlined),
          PickOption('code', status == 'active' ? 'New sign-in code (reset password)' : 'Send invite code', icon: Icons.vpn_key_outlined),
          if (m['can_grant'] == true) const PickOption('perms', 'Permissions', icon: Icons.tune_rounded),
          if (m['can_set_level'] == true) const PickOption('level', 'Admin level', icon: Icons.admin_panel_settings_outlined),
          if (app.isCore && !isMe)
            PickOption('active', m['active'] == true ? 'Deactivate' : 'Reactivate', icon: Icons.person_off_outlined, danger: m['active'] == true),
        ],
      );
      if (!context.mounted || r == null) return;
      try {
        switch (r) {
          case 'edit':
            await push(context, PersonEditor(existing: m));
            reload();
          case 'code':
            await sendCode();
          case 'perms':
            await push(context, PermissionsEditor(member: m));
            reload();
          case 'level':
            final x = await showPicker<String>(context, title: 'Admin level', selected: (m['level'] as String?) ?? '', groups: [
              PickGroup([
                const PickOption('', 'Member', subtitle: 'Only the permissions you tick', icon: Icons.person_outline_rounded),
                const PickOption('admin', 'Admin', subtitle: 'Manages everything except admins', icon: Icons.shield_outlined),
                const PickOption('super', 'Super admin', subtitle: 'Everything, including appointing admins', icon: Icons.admin_panel_settings_rounded),
              ]),
            ]);
            if (x == null) return;
            await app.api!.patch('members/${m['id']}', {'level': x.value});
            app.changed(boot: true);
            reload();
          case 'active':
            if (m['active'] == true &&
                !await confirm(context, title: 'Deactivate ${m['name']}?', message: 'They are signed out and can\'t sign in until reactivated.', action: 'Deactivate', danger: true)) {
              return;
            }
            await app.api!.patch('members/${m['id']}', {'active': m['active'] != true});
            app.changed(boot: true);
            reload();
        }
      } catch (e) {
        if (context.mounted) showApiError(context, e);
      }
    }

    return Scaffold(
      appBar: AppBar(actions: [
        if (manage) IconButton(icon: const Icon(Icons.more_vert_rounded), onPressed: menu)
        else if (isMe) IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => push(context, PersonEditor(existing: m))),
      ]),
      body: RefreshList(
        onRefresh: reload,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
        children: [
          Appear(
            index: 0,
            child: Column(children: [
              Initials(m['name'] as String, radius: 42),
              const SizedBox(height: 12),
              Text(m['name'] as String, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              if ((m['title'] as String).isNotEmpty) Text(m['title'] as String, style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
                Pill(m['member_type'] == 'executive' ? 'Executive' : 'Member', tone: m['member_type'] == 'executive' ? 'brand' : 'neutral'),
                if (m['level'] == 'super' || m['level'] == 'admin') Pill(levelLabel(m['level'] as String?), tone: 'brand', icon: Icons.admin_panel_settings_rounded),
                if ((m['unit_place'] as String?)?.isNotEmpty == true) Pill(m['unit_place'] as String, tone: 'ghost', icon: Icons.place_outlined),
                if (status != null && status != 'active') Pill(statusLabel(status), tone: statusTone(status)),
              ]),
            ]),
          ),
          if (manage && status != 'active') ...[
            const SizedBox(height: 14),
            BusyButton(label: status == 'invited' ? 'Send a new invite code' : 'Send invite code', icon: Icons.vpn_key_rounded, onPressed: sendCode),
          ],
          const SizedBox(height: 16),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
              child: (m['phone'] as String?)?.isNotEmpty == true || (m['email'] as String?)?.isNotEmpty == true
                  ? ContactActions(phone: m['phone'] as String?, email: m['email'] as String?)
                  : Padding(padding: const EdgeInsets.all(8), child: Text('No phone or email yet', style: TextStyle(color: cs.onSurfaceVariant))),
            ),
          ),
          if (m['notes'] != null && ((m['notes'] as String).isNotEmpty || m['needs_followup'] == true)) ...[
            const SectionTitle('Private notes'),
            Card(
              margin: EdgeInsets.zero,
              color: Tones.amber(context).withValues(alpha: .08),
              child: ListTile(
                leading: Icon(m['needs_followup'] == true ? Icons.flag_rounded : Icons.sticky_note_2_outlined, color: Tones.amber(context)),
                title: Text((m['notes'] as String).isEmpty ? 'Needs follow-up' : m['notes'] as String),
                subtitle: const Text('Only admins see this'),
              ),
            ),
          ],
          const SectionTitle('Wings'),
          committees.isEmpty
              ? const Card(margin: EdgeInsets.zero, child: EmptyView('Not in any wing yet.', icon: Icons.groups_outlined))
              : ListCard(children: [
                  for (final c in committees)
                    ListTile(
                      leading: CircleAvatar(backgroundColor: colorOf(context, c).withValues(alpha: .15), child: Icon(Icons.groups_rounded, color: colorOf(context, c), size: 20)),
                      title: Text(c['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(((c['position'] as String?) ?? '').isEmpty ? 'Member' : c['position'] as String),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => push(context, CommitteeDetailScreen(id: c['id'] as int)),
                    ),
                ]),
          if (perms.isNotEmpty) ...[
            const SectionTitle('Permissions'),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final p in app.choice('permissions'))
                if (perms.containsKey(p['value']))
                  Pill('${p['label']}${p['wing_scoped'] == true ? (perms[p['value']] == 'all' ? ' · all wings' : ' · own wings') : ''}', tone: 'ghost'),
            ]),
          ],
          if (duties.isNotEmpty) ...[
            const SectionTitle('Responsibilities'),
            ListCard(children: [for (final r in duties) ListTile(leading: const Icon(Icons.event_repeat_rounded), title: Text(r['title'] as String), subtitle: Text(r['repeat_label'] as String))]),
          ],
          if (tasks.isNotEmpty) ...[
            const SectionTitle('Working on'),
            ListCard(children: [for (final t in tasks) TaskTile(t, onTap: () => push(context, TaskDetailScreen(id: t['id'] as int)))]),
          ],
        ],
      ),
    );
  }
}

/// Positions are labels: pick a common one or type your own.
Future<String?> pickPosition(BuildContext context, {String current = ''}) async {
  final app = AppScope.read(context);
  final custom = TextEditingController(text: current);
  return showSheet<String>(context, title: 'Position', builder: (ctx) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final p in ((app.boot?['choices'] as Json?)?['positions'] as List? ?? []).cast<String>())
            ChoiceChip(label: Text(p), selected: current == p, showCheckmark: false, onSelected: (_) => Navigator.pop(ctx, p)),
      ]),
      const SizedBox(height: 14),
      TextField(controller: custom, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Or type a position')),
      const SizedBox(height: 14),
      FilledButton(onPressed: () => Navigator.pop(ctx, custom.text.trim()), child: const Text('Save')),
    ],
  ));
}

/// Tick the permissions someone has, each for their own wings or all wings.
class PermissionsEditor extends StatefulWidget {
  const PermissionsEditor({super.key, required this.member});
  final Json member;
  @override
  State<PermissionsEditor> createState() => _PermissionsEditorState();
}

class _PermissionsEditorState extends State<PermissionsEditor> {
  late final Map<String, String> _p = Map<String, String>.from((widget.member['permissions'] as Json?) ?? const {});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('Permissions · ${(widget.member['name'] as String).split(' ').first}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Text('Positions are labels only: these switches decide what ${(widget.member['name'] as String).split(' ').first} can do. '
              '"Own wings" means the wings they belong to.', style: TextStyle(color: cs.onSurfaceVariant, height: 1.4)),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Column(children: [
              for (final p in app.choice('permissions'))
                Builder(builder: (context) {
                  final key = p['value'] as String;
                  final on = _p.containsKey(key);
                  final mayGive = app.can(key);
                  return Column(children: [
                    SwitchListTile(
                      title: Text(p['label'] as String),
                      value: on,
                      onChanged: mayGive ? (v) => setState(() => v ? _p[key] = 'own' : _p.remove(key)) : null,
                    ),
                    if (on && p['wing_scoped'] == true)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Segments<String>(
                          items: const [('own', 'Own wings'), ('all', 'All wings')],
                          value: _p[key]!,
                          onChanged: (v) => setState(() => _p[key] = (v == 'all' && !app.allWings(key)) ? 'own' : v),
                        ),
                      ),
                  ]);
                }),
            ]),
          ),
          const SizedBox(height: 24),
          BusyButton(label: 'Save', icon: Icons.check_rounded, onPressed: () async {
            final nav = Navigator.of(context);
            try {
              await app.api!.put('members/${widget.member['id']}/permissions', {
                'permissions': [for (final e in _p.entries) {'perm': e.key, 'all_wings': e.value == 'all'}],
              });
              app.changed(boot: true);
              nav.pop();
            } catch (e) {
              if (context.mounted) showApiError(context, e);
            }
          }),
        ],
      ),
    );
  }
}

/// Shows a fresh invite / sign-in code with copy and WhatsApp buttons.
Future<void> showInviteCode(BuildContext context, Json member, String code, String message) {
  final phone = ((member['phone'] as String?) ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  return showSheet(
    context,
    title: 'Code for ${member['name']}',
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Send this to them. It works once and lets them choose a password.', style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(color: cs.primaryContainer.withValues(alpha: .55), borderRadius: BorderRadius.circular(18)),
            child: SelectableText(
              code,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: 6, color: cs.onPrimaryContainer),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1FA855), foregroundColor: Colors.white),
            icon: const Icon(Icons.chat_rounded),
            label: const Text('Send on WhatsApp'),
            onPressed: () => launchUrl(
              Uri.parse('https://wa.me/${phone.isEmpty ? '' : phone}?text=${Uri.encodeComponent(message)}'),
              mode: LaunchMode.externalApplication,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy message'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: message));
              HapticFeedback.lightImpact();
              toast(ctx, 'Copied');
            },
          ),
        ],
      );
    },
  );
}

class PersonEditor extends StatefulWidget {
  const PersonEditor({super.key, this.existing});
  final Json? existing;
  @override
  State<PersonEditor> createState() => _PersonEditorState();
}

class _PersonEditorState extends State<PersonEditor> {
  late final _name = TextEditingController(text: widget.existing?['name'] as String?);
  late final _email = TextEditingController(text: widget.existing?['email'] as String?);
  late final _phone = TextEditingController(text: widget.existing?['phone'] as String?);
  late final _title = TextEditingController(text: widget.existing?['title'] as String?);
  late final _place = TextEditingController(text: widget.existing?['unit_place'] as String?);
  late final _notes = TextEditingController(text: widget.existing?['notes'] as String?);
  late String _type = (widget.existing?['member_type'] as String?) ?? 'member';
  late bool _followup = widget.existing?['needs_followup'] == true;
  late final Map<int, String> _wings = {
    for (final c in ((widget.existing?['committees'] as List?) ?? []).cast<Json>()) c['id'] as int: (c['position'] as String?) ?? '',
  };
  bool _sendInvite = true;
  ApiException? _error;

  bool get _editing => widget.existing != null;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final isMe = widget.existing?['id'] == app.meId;
    final manage = app.canManagePeople && !isMe;
    final wingChoices = app.isCore ? app.committees : app.committeesFor('people');
    final places = ((app.boot?['choices'] as Json?)?['unit_places'] as List? ?? []).cast<String>();
    final designations = ((app.boot?['choices'] as Json?)?['designations'] as List? ?? []).cast<String>();
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? (isMe ? 'My details' : 'Edit person') : 'Add a person')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (!isMe) ...[
            Segments<String>(
              items: const [('member', 'Member'), ('executive', 'Executive')],
              value: _type,
              onChanged: (v) => setState(() => _type = v),
            ),
            if (!_editing && _type == 'executive')
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(app.isSuper ? 'Executives become admins by default.' : 'A super admin can make them an admin later.',
                    style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
              ),
            const SizedBox(height: 14),
          ],
          TextField(controller: _name, autofocus: !_editing, textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: 'Full name', prefixIcon: const Icon(Icons.badge_outlined), errorText: fieldError(_error, 'name'))),
          const SizedBox(height: 12),
          TextField(controller: _phone, keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: 'Mobile', hintText: '+966 5x xxx xxxx', prefixIcon: const Icon(Icons.phone_outlined), errorText: fieldError(_error, 'phone'))),
          const SizedBox(height: 12),
          TextField(controller: _email, keyboardType: TextInputType.emailAddress, autocorrect: false,
              decoration: InputDecoration(labelText: 'Email (optional)', prefixIcon: const Icon(Icons.mail_outline), errorText: fieldError(_error, 'email'))),
          const SizedBox(height: 12),
          Autocomplete<String>(
            initialValue: TextEditingValue(text: _title.text),
            optionsBuilder: (v) => designations.where((d) => d.toLowerCase().contains(v.text.toLowerCase())),
            onSelected: (v) => _title.text = v,
            fieldViewBuilder: (context, c, f, _) {
              c.addListener(() => _title.text = c.text);
              return TextField(controller: c, focusNode: f, textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Designation (optional)', hintText: 'e.g. Secretary', prefixIcon: Icon(Icons.work_outline_rounded)));
            },
          ),
          const SizedBox(height: 12),
          Autocomplete<String>(
            initialValue: TextEditingValue(text: _place.text),
            optionsBuilder: (v) => places.where((p) => p.toLowerCase().contains(v.text.toLowerCase())),
            onSelected: (v) => _place.text = v,
            fieldViewBuilder: (context, c, f, _) {
              c.addListener(() => _place.text = c.text);
              return TextField(controller: c, focusNode: f, textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Unit place (optional)', hintText: 'e.g. Malaz Area', prefixIcon: Icon(Icons.place_outlined)));
            },
          ),
          if (manage || (!_editing && app.canManagePeople)) ...[
            const SizedBox(height: 20),
            Text('Wings', style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text('Tap a wing to add them; tap again to set their position (a label).', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in wingChoices)
                FilterChip(
                  avatar: Dot(colorOf(context, c)),
                  label: Text(_wings.containsKey(c['id']) && _wings[c['id']]!.isNotEmpty ? '${c['name']} · ${_wings[c['id']]}' : c['name'] as String),
                  selected: _wings.containsKey(c['id']),
                  showCheckmark: false,
                  onSelected: (_) async {
                    HapticFeedback.selectionClick();
                    final id = c['id'] as int;
                    if (!_wings.containsKey(id)) {
                      setState(() => _wings[id] = '');
                      return;
                    }
                    final r = await showActions(context, title: c['name'] as String, actions: const [
                      PickOption('pos', 'Set position', icon: Icons.badge_outlined),
                      PickOption('remove', 'Remove from wing', icon: Icons.close_rounded, danger: true),
                    ]);
                    if (!context.mounted) return;
                    if (r == 'remove') setState(() => _wings.remove(id));
                    if (r == 'pos') {
                      final pos = await pickPosition(context, current: _wings[id] ?? '');
                      if (pos != null) setState(() => _wings[id] = pos);
                    }
                  },
                ),
            ]),
            if (app.isCore) ...[
              const SizedBox(height: 18),
              TextField(controller: _notes, minLines: 2, maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Private notes (only admins see these)', alignLabelWithHint: true, prefixIcon: Icon(Icons.sticky_note_2_outlined))),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Needs follow-up'),
                value: _followup,
                onChanged: (v) => setState(() => _followup = v),
              ),
            ],
            if (!_editing)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Create an invite code now'),
                subtitle: const Text('You can also send it later from their page'),
                value: _sendInvite,
                onChanged: (v) => setState(() => _sendInvite = v),
              ),
          ],
          const SizedBox(height: 24),
          BusyButton(
            label: _editing ? 'Save' : (_sendInvite ? 'Add & get invite code' : 'Add person'),
            icon: _editing ? Icons.check_rounded : Icons.person_add_alt_1_rounded,
            onPressed: () async {
              setState(() => _error = null);
              final nav = Navigator.of(context);
              final body = <String, dynamic>{
                'name': _name.text, 'email': _email.text, 'phone': _phone.text, 'title': _title.text,
                'unit_place': _place.text,
                if (!isMe) 'member_type': _type,
                if (manage || !_editing) 'committees': [for (final e in _wings.entries) {'id': e.key, 'position': e.value}],
                if (app.isCore && !isMe) 'notes': _notes.text,
                if (app.isCore && !isMe) 'needs_followup': _followup,
              };
              try {
                if (_editing) {
                  await app.api!.patch('members/${widget.existing!['id']}', body);
                  app.changed(boot: true);
                  nav.pop();
                } else {
                  final r = await app.api!.post('members', {...body, 'invite': _sendInvite});
                  app.changed(boot: true);
                  final member = r['member'] as Json;
                  nav.pop();
                  if (r['code'] != null) {
                    // ignore: use_build_context_synchronously
                    showInviteCode(nav.context, member, r['code'] as String, r['message'] as String);
                  }
                }
              } on ApiException catch (e) {
                setState(() => _error = e);
                if (context.mounted) showApiError(context, e);
              }
            },
          ),
        ],
      ),
    );
  }
}
