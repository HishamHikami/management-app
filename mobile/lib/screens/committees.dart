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
                  tooltip: 'New committee',
                  onPressed: () => push(context, const CommitteeEditor()),
                  child: const Icon(Icons.add_rounded),
                )
              : null);
    return Scaffold(
      appBar: AppBar(title: const Text('Committees'), actions: appBarActions(context)),
      floatingActionButton: AnimatedSwitcher(duration: const Duration(milliseconds: 200), child: fab),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Segments<String>(
              items: [('committees', 'Committees'), ('people', 'People · ${app.members.length}')],
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
          return const EmptyView('No committees yet.', icon: Icons.groups_outlined);
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
            colors: [Color(0xFF14A3A3), brand, Color(0xFF0A4F5C)],
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
                  if (c['my_role'] == 'head')
                    const Pill('Head', tone: 'brand')
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

class _PeopleList extends StatelessWidget {
  const _PeopleList({super.key, required this.q});
  final String q;
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Loader(
      load: () => app.api!.get('members'),
      builder: (context, d, reload) {
        final all = (d['members'] as List).cast<Json>();
        final list = q.isEmpty
            ? all
            : all.where((m) => '${m['name']} ${m['title']} ${m['phone']} ${m['email']}'.toLowerCase().contains(q)).toList();
        return RefreshList(
          onRefresh: reload,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            if (list.isEmpty)
              const EmptyView('Nobody found.', icon: Icons.person_search_outlined)
            else
              ListCard(
                children: [
                  for (final m in list)
                    PersonTile(
                      m,
                      subtitle: [
                        if ((m['title'] as String).isNotEmpty) m['title'] as String,
                        ...(m['committees'] as List).map((c) => '${(c as Json)['name']}${c['role'] == 'head' ? ' (head)' : ''}'),
                      ].join(' · '),
                      trailing: m['is_admin'] == true ? const Pill('Admin', tone: 'brand') : null,
                      onTap: () => push(context, MemberDetailScreen(id: m['id'] as int)),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

// ======================================================================= committee detail

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
      final isHead = m['role'] == 'head';
      final r = await showActions(
        context,
        title: m['name'] as String,
        actions: [
          const PickOption('view', 'View profile', icon: Icons.person_outline_rounded),
          if (manage && app.isCore)
            PickOption(isHead ? 'member' : 'head', isHead ? 'Make a regular member' : 'Make head', icon: Icons.workspace_premium_outlined),
          if (manage) const PickOption('remove', 'Remove from committee', icon: Icons.person_remove_outlined, danger: true),
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
          await app.api!.patch('committees/$id/members/${m['id']}', {'role': r});
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
          const PickOption('edit', 'Edit committee', icon: Icons.edit_outlined),
          if (c['is_core'] != true) const PickOption('archive', 'Archive committee', icon: Icons.archive_outlined, danger: true),
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
                    trailing: SeeAll(onTap: () => push(context, TasksScreen(standalone: true, initialScope: app.isCore ? 'all' : 'team', committeeId: id))),
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
                    trailing: manage && (c['is_core'] != true || app.isAdmin) ? SeeAll(label: 'Add', onTap: addMembers) : null,
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
                                  trailing: m['role'] == 'head' ? Pill('Head', tone: 'brand', icon: Icons.workspace_premium_rounded) : null,
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
      appBar: AppBar(title: Text(editing ? 'Edit committee' : 'New committee')),
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
            label: editing ? 'Save' : 'Create committee',
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

class _MemberPage extends StatelessWidget {
  const _MemberPage({required this.m, required this.reload});
  final Json m;
  final Future<void> Function() reload;
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final committees = (m['committees'] as List).cast<Json>();
    final tasks = (m['open_tasks'] as List).cast<Json>();
    final manage = m['can_manage'] == true;
    final isMe = m['id'] == app.meId;

    Future<void> menu() async {
      final r = await showActions(
        context,
        title: m['name'] as String,
        actions: [
          const PickOption('edit', 'Edit details', icon: Icons.edit_outlined),
          PickOption('code', m['has_password'] == true ? 'New sign-in code (reset password)' : 'New invite code', icon: Icons.vpn_key_outlined),
          if (app.isAdmin && !isMe)
            PickOption('admin', m['is_admin'] == true ? 'Remove admin rights' : 'Make app admin', icon: Icons.admin_panel_settings_outlined),
          if (app.isAdmin && !isMe)
            PickOption('active', m['active'] == true ? 'Deactivate' : 'Reactivate', icon: Icons.person_off_outlined, danger: m['active'] == true),
        ],
      );
      if (!context.mounted || r == null) return;
      try {
        switch (r) {
          case 'edit':
            push(context, PersonEditor(existing: m));
          case 'code':
            final x = await app.api!.post('members/${m['id']}/invite');
            if (context.mounted) showInviteCode(context, m, x['code'] as String, x['message'] as String);
          case 'admin':
            await app.api!.patch('members/${m['id']}', {'is_admin': m['is_admin'] != true});
            app.changed(boot: true);
          case 'active':
            if (m['active'] == true &&
                !await confirm(context, title: 'Deactivate ${m['name']}?', message: 'They are signed out and can\'t sign in until reactivated.', action: 'Deactivate', danger: true)) {
              return;
            }
            await app.api!.patch('members/${m['id']}', {'active': m['active'] != true});
            app.changed(boot: true);
        }
      } catch (e) {
        if (context.mounted) showApiError(context, e);
      }
    }

    return Scaffold(
      appBar: AppBar(actions: [if (manage || isMe) IconButton(icon: const Icon(Icons.more_vert_rounded), onPressed: isMe && !manage ? () => push(context, PersonEditor(existing: m)) : menu)]),
      body: RefreshList(
        onRefresh: reload,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
        children: [
          Appear(
            index: 0,
            child: Column(
              children: [
                Initials(m['name'] as String, radius: 42),
                const SizedBox(height: 12),
                Text(m['name'] as String, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                if ((m['title'] as String).isNotEmpty)
                  Text(m['title'] as String, style: TextStyle(color: cs.onSurfaceVariant)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: [
                    if (m['is_admin'] == true) const Pill('Admin', tone: 'brand', icon: Icons.admin_panel_settings_rounded),
                    if (m['active'] != true) const Pill('Deactivated', tone: 'red'),
                    if (m['invite_pending'] == true) const Pill('Invite not used yet', tone: 'amber'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Appear(
            index: 1,
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                child: ContactActions(phone: m['phone'] as String?, email: m['email'] as String?),
              ),
            ),
          ),
          const SectionTitle('Committees'),
          Appear(
            index: 2,
            child: committees.isEmpty
                ? const Card(margin: EdgeInsets.zero, child: EmptyView('Not in any committee yet.', icon: Icons.groups_outlined))
                : ListCard(
                    children: [
                      for (final c in committees)
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: colorOf(context, c).withValues(alpha: .15),
                            child: Icon(c['is_core'] == true ? Icons.star_rounded : Icons.groups_rounded, color: colorOf(context, c), size: 20),
                          ),
                          title: Text(c['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text([c['role'] == 'head' ? 'Head' : 'Member', if ((c['position'] as String).isNotEmpty) c['position']].join(' · ')),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => push(context, CommitteeDetailScreen(id: c['id'] as int)),
                        ),
                    ],
                  ),
          ),
          if (tasks.isNotEmpty) ...[
            const SectionTitle('Working on'),
            Appear(
              index: 3,
              child: ListCard(
                children: [for (final t in tasks) TaskTile(t, onTap: () => push(context, TaskDetailScreen(id: t['id'] as int)))],
              ),
            ),
          ],
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
  final Map<int, String> _roles = {}; // committee id → head/member
  bool _admin = false;
  ApiException? _error;

  bool get _editing => widget.existing != null;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final committees = app.committees.where((c) => c['is_core'] != true || app.isAdmin).toList();
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit person' : 'Add a person')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            controller: _name,
            autofocus: !_editing,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: 'Full name', prefixIcon: const Icon(Icons.badge_outlined), errorText: fieldError(_error, 'name')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: 'Mobile', hintText: '+966 5x xxx xxxx', prefixIcon: const Icon(Icons.phone_outlined), errorText: fieldError(_error, 'phone')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: InputDecoration(labelText: 'Email (optional)', prefixIcon: const Icon(Icons.mail_outline), errorText: fieldError(_error, 'email')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Position (optional)', hintText: 'e.g. General Secretary', prefixIcon: Icon(Icons.work_outline_rounded)),
          ),
          if (!_editing) ...[
            const SizedBox(height: 20),
            Text('Committees', style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text('Tap once to add as member, again to make head.', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in committees)
                  FilterChip(
                    avatar: _roles[c['id']] == 'head'
                        ? const Icon(Icons.workspace_premium_rounded, size: 18)
                        : Dot(colorOf(context, c)),
                    label: Text('${c['name']}${_roles[c['id']] == 'head' ? ' · Head' : ''}'),
                    selected: _roles.containsKey(c['id']),
                    showCheckmark: false,
                    onSelected: (_) {
                      HapticFeedback.selectionClick();
                      final id = c['id'] as int;
                      setState(() {
                        final r = _roles[id];
                        if (r == null) {
                          _roles[id] = 'member';
                        } else if (r == 'member' && app.isCore) {
                          _roles[id] = 'head';
                        } else {
                          _roles.remove(id);
                        }
                      });
                    },
                  ),
              ],
            ),
            if (app.isAdmin) ...[
              const SizedBox(height: 14),
              Card(
                margin: EdgeInsets.zero,
                child: SwitchListTile(
                  secondary: const Icon(Icons.admin_panel_settings_outlined),
                  title: const Text('App admin'),
                  subtitle: const Text('Can add people, change roles and the core committee'),
                  value: _admin,
                  onChanged: (v) => setState(() => _admin = v),
                ),
              ),
            ],
          ],
          const SizedBox(height: 28),
          BusyButton(
            label: _editing ? 'Save' : 'Add & get invite code',
            icon: _editing ? Icons.check_rounded : Icons.person_add_alt_1_rounded,
            onPressed: () async {
              setState(() => _error = null);
              final nav = Navigator.of(context);
              final body = {'name': _name.text, 'email': _email.text, 'phone': _phone.text, 'title': _title.text};
              try {
                if (_editing) {
                  await app.api!.patch('members/${widget.existing!['id']}', body);
                  app.changed(boot: true);
                  nav.pop();
                } else {
                  final r = await app.api!.post('members', {
                    ...body,
                    'is_admin': _admin,
                    'committees': [for (final e in _roles.entries) {'id': e.key, 'role': e.value}],
                  });
                  app.changed(boot: true);
                  final member = r['member'] as Json;
                  nav.pop();
                  // ignore: use_build_context_synchronously
                  showInviteCode(nav.context, member, r['code'] as String, r['message'] as String);
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
