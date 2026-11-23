import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../api.dart';
import '../state.dart';
import '../ui.dart';
import 'home.dart';

Future<void> openNewAnnouncement(BuildContext context, {int? committeeId}) async {
  final created = await push<Json>(context, AnnouncementComposer(committeeId: committeeId));
  if (created != null && context.mounted) {
    push(context, AnnouncementDetailScreen(id: created['id'] as int));
  }
}

class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key, this.standalone = false});
  final bool standalone;
  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final unread = app.count('announcements');
    final toAck = app.count('to_ack');
    final filters = <(String, String)>[
      ('all', 'All'),
      ('unread', unread > 0 ? 'Unread · $unread' : 'Unread'),
      ('ack', toAck > 0 ? 'To confirm · $toAck' : 'To confirm'),
      if (app.canLead) ('sent', 'Sent'),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Announcements'),
        actions: [if (!widget.standalone) ...appBarActions(context)],
      ),
      floatingActionButton: app.canLead
          ? FloatingActionButton.extended(
              heroTag: 'ann-fab',
              onPressed: () => openNewAnnouncement(context),
              icon: const Icon(Icons.edit_rounded),
              label: const Text('Post'),
            )
          : null,
      body: Column(
        children: [
          ChipRow(
            children: [
              for (final f in filters)
                ChoiceChip(
                  label: Text(f.$2),
                  selected: _filter == f.$1,
                  showCheckmark: false,
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    setState(() => _filter = f.$1);
                  },
                ),
            ],
          ),
          Expanded(
            child: Loader(
              key: ValueKey('ann-$_filter'),
              load: () => app.api!.get('announcements', query: {'filter': _filter}),
              builder: (context, d, reload) {
                final items = (d['announcements'] as List).cast<Json>();
                return RefreshList(
                  onRefresh: reload,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                  children: [
                    if (items.isEmpty)
                      EmptyView(
                        switch (_filter) {
                          'unread' => 'You\'re all caught up.',
                          'ack' => 'Nothing waiting for your confirmation.',
                          'sent' => 'You haven\'t posted anything yet.',
                          _ => 'No announcements yet.',
                        },
                        icon: Icons.campaign_outlined,
                      ),
                    for (var i = 0; i < items.length; i++)
                      Appear(
                        index: i,
                        child: AnnouncementCard(
                          items[i],
                          onTap: () => push(context, AnnouncementDetailScreen(id: items[i]['id'] as int)),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ======================================================================= detail

class AnnouncementDetailScreen extends StatelessWidget {
  const AnnouncementDetailScreen({super.key, required this.id});
  final int id;
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Loader(
      load: () async {
        final r = await app.api!.get('announcements/$id');
        Future.microtask(app.refreshCounts); // opening marks it as read
        return r;
      },
      builder: (context, d, reload) => _AnnouncementPage(a: d['announcement'] as Json, reload: reload),
    );
  }
}

class _AnnouncementPage extends StatefulWidget {
  const _AnnouncementPage({required this.a, required this.reload});
  final Json a;
  final Future<void> Function() reload;
  @override
  State<_AnnouncementPage> createState() => _AnnouncementPageState();
}

class _AnnouncementPageState extends State<_AnnouncementPage> {
  late Json a = widget.a;

  @override
  void didUpdateWidget(_AnnouncementPage old) {
    super.didUpdateWidget(old);
    a = widget.a;
  }

  AppState get app => AppScope.read(context);

  Future<void> _ack() async {
    try {
      final r = await app.api!.post('announcements/${a['id']}/ack');
      HapticFeedback.heavyImpact();
      setState(() => a = r['announcement'] as Json);
      app.changed();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _menu() async {
    final r = await showActions(
      context,
      title: 'Announcement',
      actions: [
        if (app.isCore)
          PickOption('pin', a['pinned'] == true ? 'Unpin' : 'Pin to top', icon: Icons.push_pin_outlined),
        const PickOption('edit', 'Edit', icon: Icons.edit_outlined),
        const PickOption('delete', 'Delete', icon: Icons.delete_outline_rounded, danger: true),
      ],
    );
    if (!mounted) return;
    try {
      switch (r) {
        case 'pin':
          final x = await app.api!.patch('announcements/${a['id']}', {'pinned': a['pinned'] != true});
          setState(() => a = x['announcement'] as Json);
          app.changed();
        case 'edit':
          final saved = await push<Json>(context, AnnouncementComposer(existing: a));
          if (saved != null) widget.reload();
        case 'delete':
          if (await confirm(context, title: 'Delete this announcement?', message: 'It disappears for everyone.', action: 'Delete', danger: true)) {
            await app.api!.delete('announcements/${a['id']}');
            app.changed();
            if (mounted) Navigator.pop(context);
          }
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final author = a['author'] as Json?;
    final from = a['posted_as'] as Json?;
    final needAck = a['requires_ack'] == true && a['is_recipient'] == true;
    final stats = a['stats'] as Json?;
    return Scaffold(
      appBar: AppBar(
        actions: [if (a['can_manage'] == true) IconButton(icon: const Icon(Icons.more_vert_rounded), onPressed: _menu)],
      ),
      body: RefreshList(
        onRefresh: widget.reload,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
        children: [
          Appear(
            index: 0,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (a['pinned'] == true) const Pill('Pinned', tone: 'brand', icon: Icons.push_pin_rounded),
                if (a['urgent'] == true) const Pill('Urgent', tone: 'red', icon: Icons.priority_high_rounded),
                Pill(a['audience_label'] as String, tone: 'ghost', icon: a['audience'] == 'all' ? Icons.public_rounded : Icons.group_outlined),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Appear(
            index: 1,
            child: Text(
              a['title'] as String,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.3),
            ),
          ),
          const SizedBox(height: 14),
          Appear(
            index: 2,
            child: Row(
              children: [
                if (author != null) Initials(author['name'] as String, radius: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(author?['name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(
                        [
                          if (from != null) 'for ${from['name']}',
                          fmtDateTime(a['created_at'] as String?),
                          if (a['edited_at'] != null) 'edited',
                        ].join(' · '),
                        style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Appear(
            index: 3,
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: SelectableText(a['body'] as String, style: const TextStyle(fontSize: 16, height: 1.55)),
              ),
            ),
          ),
          if (needAck) ...[
            const SizedBox(height: 16),
            Appear(index: 4, child: _AckButton(acked: a['acked'] == true, onAck: _ack)),
          ],
          if (stats != null) ...[
            const SectionTitle('Reach'),
            Appear(
              index: 5,
              child: Card(
                margin: EdgeInsets.zero,
                child: Pressable(
                  borderRadius: 18,
                  onTap: () => push(context, _ReceiptsScreen(id: a['id'] as int, title: a['title'] as String)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _Progress(label: 'Read', value: stats['read'] as int, total: stats['total'] as int, color: cs.primary),
                        if (a['requires_ack'] == true) ...[
                          const SizedBox(height: 12),
                          _Progress(label: 'Acknowledged', value: stats['acked'] as int, total: stats['total'] as int, color: Tones.green(context)),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text('See who', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700)),
                            Icon(Icons.chevron_right_rounded, color: cs.primary),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AckButton extends StatelessWidget {
  const _AckButton({required this.acked, required this.onAck});
  final bool acked;
  final Future<void> Function() onAck;
  @override
  Widget build(BuildContext context) {
    final green = Tones.green(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 380),
      transitionBuilder: (c, a) => ScaleTransition(scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack), child: FadeTransition(opacity: a, child: c)),
      child: acked
          ? Container(
              key: const ValueKey('done'),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: green.withValues(alpha: .12), borderRadius: BorderRadius.circular(16)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.verified_rounded, color: green),
                  const SizedBox(width: 8),
                  Text('You acknowledged this', style: TextStyle(color: green, fontWeight: FontWeight.w700)),
                ],
              ),
            )
          : SizedBox(
              key: const ValueKey('ask'),
              width: double.infinity,
              child: BusyButton(label: 'I\'ve read this — acknowledge', icon: Icons.done_all_rounded, onPressed: onAck),
            ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.label, required this.value, required this.total, required this.color});
  final String label;
  final int value;
  final int total;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final f = total == 0 ? 0.0 : value / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('$value of $total', style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: f),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 8, color: color, backgroundColor: color.withValues(alpha: .14)),
          ),
        ),
      ],
    );
  }
}

class _ReceiptsScreen extends StatefulWidget {
  const _ReceiptsScreen({required this.id, required this.title});
  final int id;
  final String title;
  @override
  State<_ReceiptsScreen> createState() => _ReceiptsScreenState();
}

class _ReceiptsScreenState extends State<_ReceiptsScreen> {
  String _tab = 'unread';
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Who has read it')),
      body: Loader(
        load: () => app.api!.get('announcements/${widget.id}/receipts'),
        builder: (context, d, reload) {
          final all = (d['receipts'] as List).cast<Json>();
          final lists = {
            'unread': all.where((r) => r['read_at'] == null).toList(),
            'read': all.where((r) => r['read_at'] != null && r['acked_at'] == null).toList(),
            'acked': all.where((r) => r['acked_at'] != null).toList(),
          };
          final rows = lists[_tab]!;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Segments<String>(
                  items: [
                    ('unread', 'Not read · ${lists['unread']!.length}'),
                    ('read', 'Read · ${lists['read']!.length}'),
                    ('acked', 'Confirmed · ${lists['acked']!.length}'),
                  ],
                  value: _tab,
                  onChanged: (v) => setState(() => _tab = v),
                ),
              ),
              Expanded(
                child: RefreshList(
                  onRefresh: reload,
                  children: [
                    if (rows.isEmpty) const EmptyView('Nobody here.', icon: Icons.people_outline_rounded)
                    else
                      ListCard(
                        children: [
                          for (final r in rows)
                            PersonTile(
                              r['member'] as Json,
                              subtitle: r['acked_at'] != null
                                  ? 'Confirmed ${ago(r['acked_at'] as String?)}'
                                  : r['read_at'] != null
                                  ? 'Read ${ago(r['read_at'] as String?)}'
                                  : ((r['member'] as Json)['phone'] as String? ?? ''),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ======================================================================= composer

class AnnouncementComposer extends StatefulWidget {
  const AnnouncementComposer({super.key, this.existing, this.committeeId});
  final Json? existing;
  final int? committeeId;
  @override
  State<AnnouncementComposer> createState() => _AnnouncementComposerState();
}

class _AnnouncementComposerState extends State<AnnouncementComposer> {
  late final _title = TextEditingController(text: widget.existing?['title'] as String?);
  late final _body = TextEditingController(text: widget.existing?['body'] as String?);
  String _audience = 'all';
  Set<int> _committees = {};
  Set<int> _people = {};
  bool _urgent = false;
  bool _ack = false;
  bool _pinned = false;
  ApiException? _error;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    final e = widget.existing;
    if (e != null) {
      _urgent = e['urgent'] == true;
      _ack = e['requires_ack'] == true;
      _pinned = e['pinned'] == true;
    } else if (!app.isCore || widget.committeeId != null) {
      _audience = 'committees';
      final start = widget.committeeId ?? (app.headedIds.isNotEmpty ? app.headedIds.first : null);
      if (start != null && app.leadableIds.contains(start)) _committees = {start};
    }
  }

  List<Json> _committeeChoices(AppState app) =>
      app.isCore ? app.committees : app.committees.where((c) => app.headedIds.contains(c['id'])).toList();

  List<Json> _peopleChoices(AppState app) => app.isCore
      ? app.members
      : app.members.where((m) => ((m['committee_ids'] as List?) ?? []).any(app.headedIds.contains)).toList();

  int _reach(AppState app) => switch (_audience) {
    'all' => app.members.length,
    'committees' => app.members.where((m) => ((m['committee_ids'] as List?) ?? []).any(_committees.contains)).length,
    _ => _people.length,
  };

  Future<void> _send() async {
    final app = AppScope.read(context);
    setState(() => _error = null);
    try {
      Json r;
      if (_editing) {
        r = await app.api!.patch('announcements/${widget.existing!['id']}', {
          'title': _title.text,
          'body': _body.text,
          'urgent': _urgent,
          'requires_ack': _ack,
          if (app.isCore) 'pinned': _pinned,
        });
      } else {
        r = await app.api!.post('announcements', {
          'title': _title.text,
          'body': _body.text,
          'audience': _audience,
          'committees': _committees.toList(),
          'people': _people.toList(),
          'urgent': _urgent,
          'requires_ack': _ack,
          'pinned': _pinned,
        });
      }
      app.changed();
      if (mounted) {
        toast(context, _editing ? 'Saved' : 'Sent to ${r['sent_to'] ?? ''} people');
        Navigator.pop(context, r['announcement']);
      }
    } on ApiException catch (e) {
      setState(() => _error = e);
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final audiences = <(String, String)>[
      if (app.isCore) ('all', 'Everyone'),
      ('committees', 'Committees'),
      ('people', 'People'),
    ];
    final reach = _reach(app);
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit announcement' : 'New announcement')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            controller: _title,
            autofocus: !_editing,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            decoration: InputDecoration(labelText: 'Title', errorText: fieldError(_error, 'title')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _body,
            minLines: 5,
            maxLines: 14,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: 'Message', alignLabelWithHint: true, errorText: fieldError(_error, 'body')),
          ),
          if (!_editing) ...[
            const SizedBox(height: 18),
            Text('Send to', style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            Segments<String>(items: audiences, value: _audience, onChanged: (v) => setState(() => _audience = v)),
            AnimatedSize(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: switch (_audience) {
                  'committees' => Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in _committeeChoices(app))
                        FilterChip(
                          avatar: Dot(colorOf(context, c)),
                          label: Text(c['name'] as String),
                          selected: _committees.contains(c['id']),
                          showCheckmark: false,
                          onSelected: (on) {
                            HapticFeedback.selectionClick();
                            setState(() => on ? _committees.add(c['id'] as int) : _committees.remove(c['id']));
                          },
                        ),
                    ],
                  ),
                  'people' => PeopleField(
                    label: 'People',
                    people: _peopleChoices(app),
                    value: _people,
                    placeholder: 'Choose people',
                    onChanged: (v) => setState(() => _people = v),
                  ),
                  _ => const SizedBox(width: double.infinity),
                },
              ),
            ),
          ],
          const SizedBox(height: 14),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile(
                  secondary: Icon(Icons.priority_high_rounded, color: Tones.red(context)),
                  title: const Text('Urgent'),
                  subtitle: const Text('Highlighted in red, sent as a high-priority notification'),
                  value: _urgent,
                  onChanged: (v) => setState(() => _urgent = v),
                ),
                SwitchListTile(
                  secondary: Icon(Icons.done_all_rounded, color: Tones.green(context)),
                  title: const Text('Ask people to acknowledge'),
                  subtitle: const Text('Each person taps "I\'ve read this"; you see who has'),
                  value: _ack,
                  onChanged: (v) => setState(() => _ack = v),
                ),
                if (app.isCore)
                  SwitchListTile(
                    secondary: Icon(Icons.push_pin_outlined, color: cs.primary),
                    title: const Text('Pin to top'),
                    value: _pinned,
                    onChanged: (v) => setState(() => _pinned = v),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          BusyButton(
            label: _editing ? 'Save' : 'Send to $reach ${reach == 1 ? 'person' : 'people'}',
            icon: _editing ? Icons.check_rounded : Icons.send_rounded,
            onPressed: _editing || reach > 0 ? _send : null,
          ),
        ],
      ),
    );
  }
}
