import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../state.dart';
import '../ui.dart';
import 'home.dart';

Future<void> openNewMeeting(BuildContext context, {int? committeeId}) async {
  final created = await push<Json>(context, MeetingEditor(committeeId: committeeId));
  if (created != null && context.mounted) {
    push(context, MeetingDetailScreen(id: created['id'] as int));
  }
}

class MeetingsScreen extends StatefulWidget {
  const MeetingsScreen({super.key, this.standalone = false});
  final bool standalone;
  @override
  State<MeetingsScreen> createState() => _MeetingsScreenState();
}

class _MeetingsScreenState extends State<MeetingsScreen> {
  String _when = 'upcoming';

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meetings'),
        actions: [if (!widget.standalone) ...appBarActions(context)],
      ),
      floatingActionButton: app.wingsFor('meetings').isNotEmpty
          ? FloatingActionButton(
              heroTag: 'meet-fab',
              tooltip: 'New meeting',
              onPressed: () => openNewMeeting(context),
              child: const Icon(Icons.add_rounded),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Segments<String>(
              items: const [('upcoming', 'Upcoming'), ('past', 'Past')],
              value: _when,
              onChanged: (v) => setState(() => _when = v),
            ),
          ),
          Expanded(
            child: Loader(
              key: ValueKey('meet-$_when'),
              load: () => app.api!.get('meetings', query: {'when': _when}),
              builder: (context, d, reload) {
                final items = (d['meetings'] as List).cast<Json>();
                if (items.isEmpty) {
                  return RefreshList(
                    onRefresh: reload,
                    children: [
                      EmptyView(_when == 'past' ? 'No past meetings yet.' : 'No meetings coming up.', icon: Icons.event_available_outlined),
                    ],
                  );
                }
                final groups = <String, List<Json>>{};
                for (final m in items) {
                  final t = DateTime.parse(m['start'] as String).toLocal();
                  final days = DateUtils.dateOnly(t).difference(DateUtils.dateOnly(DateTime.now())).inDays;
                  final key = _when == 'past'
                      ? DateFormat('MMMM yyyy').format(t)
                      : days <= 0
                      ? 'Today'
                      : days == 1
                      ? 'Tomorrow'
                      : days < 7
                      ? 'This week'
                      : DateFormat('MMMM').format(t);
                  groups.putIfAbsent(key, () => []).add(m);
                }
                var i = 0;
                return RefreshList(
                  onRefresh: reload,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                  children: [
                    for (final g in groups.entries) ...[
                      SectionTitle(g.key),
                      Appear(
                        index: i++,
                        child: ListCard(
                          children: [
                            for (final m in g.value)
                              MeetingTile(m, onTap: () => push(context, MeetingDetailScreen(id: m['id'] as int))),
                          ],
                        ),
                      ),
                    ],
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

class MeetingDetailScreen extends StatelessWidget {
  const MeetingDetailScreen({super.key, required this.id});
  final int id;
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Loader(
      load: () => app.api!.get('meetings/$id'),
      builder: (context, d, reload) => _MeetingPage(m: d['meeting'] as Json, reload: reload),
    );
  }
}

class _MeetingPage extends StatefulWidget {
  const _MeetingPage({required this.m, required this.reload});
  final Json m;
  final Future<void> Function() reload;
  @override
  State<_MeetingPage> createState() => _MeetingPageState();
}

class _MeetingPageState extends State<_MeetingPage> {
  late Json m = widget.m;

  @override
  void didUpdateWidget(_MeetingPage old) {
    super.didUpdateWidget(old);
    m = widget.m;
  }

  AppState get app => AppScope.read(context);

  Future<void> _post(String path, Json body, {String? done}) async {
    try {
      final r = await app.api!.post('meetings/${m['id']}/$path', body);
      setState(() => m = r['meeting'] as Json);
      app.changed();
      if (done != null && mounted) toast(context, done);
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _attendance() async {
    final rows = (m['attendees'] as List).cast<Json>();
    final marks = {for (final a in rows) (a['member'] as Json)['id'] as int: a['attendance'] as String};
    final ok = await showSheet<bool>(
      context,
      title: 'Attendance',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final present = marks.values.where((v) => v == 'present').length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('$present of ${rows.length} present', style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => set(() {
                      for (final a in rows) {
                        final id = (a['member'] as Json)['id'] as int;
                        if (a['rsvp'] == 'going' && marks[id] == '') marks[id] = 'present';
                      }
                    }),
                    child: const Text('"Going" = present'),
                  ),
                ],
              ),
              for (final a in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Initials((a['member'] as Json)['name'] as String, radius: 16),
                      const SizedBox(width: 10),
                      Expanded(child: Text((a['member'] as Json)['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600))),
                      for (final s in const [('present', Icons.check_rounded), ('absent', Icons.close_rounded), ('excused', Icons.remove_rounded)])
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: _MarkButton(
                            icon: s.$2,
                            kind: s.$1,
                            on: marks[(a['member'] as Json)['id']] == s.$1,
                            onTap: () => set(() {
                              final id = (a['member'] as Json)['id'] as int;
                              marks[id] = marks[id] == s.$1 ? '' : s.$1;
                            }),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save attendance')),
            ],
          );
        },
      ),
    );
    if (ok == true) {
      await _post('attendance', {'attendance': {for (final e in marks.entries) '${e.key}': e.value}}, done: 'Attendance saved');
    }
  }

  Future<void> _minutes() async {
    final saved = await push<bool>(context, _MinutesEditor(meeting: m));
    if (saved == true) widget.reload();
  }

  Future<void> _menu() async {
    final cancelled = m['cancelled'] == true;
    final r = await showActions(
      context,
      title: 'Meeting',
      actions: [
        const PickOption('edit', 'Edit', icon: Icons.edit_outlined),
        const PickOption('attendance', 'Take attendance', icon: Icons.fact_check_outlined),
        PickOption('minutes', m['has_minutes'] == true ? 'Edit minutes' : 'Write minutes', icon: Icons.description_outlined),
        cancelled
            ? const PickOption('restore', 'Put back on', icon: Icons.event_available_outlined)
            : const PickOption('cancel', 'Cancel meeting', icon: Icons.event_busy_outlined, danger: true),
      ],
    );
    if (!mounted) return;
    switch (r) {
      case 'edit':
        final saved = await push<Json>(context, MeetingEditor(existing: m));
        if (saved != null) widget.reload();
      case 'attendance':
        _attendance();
      case 'minutes':
        _minutes();
      case 'cancel':
        if (await confirm(context, title: 'Cancel this meeting?', message: 'Everyone invited will be told.', action: 'Cancel meeting', danger: true)) {
          _post('cancel', {}, done: 'Meeting cancelled');
        }
      case 'restore':
        _post('cancel', {'restore': true}, done: 'Meeting is back on');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final start = DateTime.parse(m['start'] as String).toLocal();
    final end = m['end'] == null ? null : DateTime.parse(m['end'] as String).toLocal();
    final c = m['committee'] as Json?;
    final color = c == null ? cs.primary : colorOf(context, c);
    final attendees = (m['attendees'] as List).cast<Json>();
    final counts = m['counts'] as Json;
    final cancelled = m['cancelled'] == true;
    final past = m['is_past'] == true;
    final manage = m['can_manage'] == true;
    final location = m['location'] as String;
    final link = m['online_link'] as String;
    final mine = m['my_rsvp'] as String?;
    var i = 0;
    return Scaffold(
      appBar: AppBar(actions: [if (manage) IconButton(icon: const Icon(Icons.more_vert_rounded), onPressed: _menu)]),
      body: RefreshList(
        onRefresh: widget.reload,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
        children: [
          Appear(
            index: i++,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 64,
                  height: 70,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color, Color.lerp(color, Colors.black, .25)!]),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [BoxShadow(color: color.withValues(alpha: .3), blurRadius: 14, offset: const Offset(0, 6))],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(DateFormat('MMM').format(start).toUpperCase(),
                          style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .8)),
                      Text('${start.day}', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, height: 1.05)),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          c == null ? const Pill('General meeting', tone: 'brand', icon: Icons.public_rounded) : CommitteeChip(c),
                          if (cancelled) const Pill('Cancelled', tone: 'red'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        m['title'] as String,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.3,
                          decoration: cancelled ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!cancelled && !past && mine != null) ...[
            const SizedBox(height: 18),
            Appear(
              index: i++,
              child: _RsvpBar(value: mine, onChanged: (v) {
                HapticFeedback.mediumImpact();
                _post('rsvp', {'rsvp': v});
              }),
            ),
          ],
          const SizedBox(height: 14),
          Appear(
            index: i++,
            child: Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  InfoRow(
                    icon: Icons.schedule_rounded,
                    label: 'WHEN',
                    child: Text(
                      '${DateFormat('EEEE, d MMMM').format(start)}\n${DateFormat('HH:mm').format(start)}${end != null ? ' – ${DateFormat('HH:mm').format(end)}' : ''}',
                    ),
                  ),
                  if (location.isNotEmpty)
                    InfoRow(
                      icon: Icons.place_outlined,
                      label: 'WHERE',
                      onTap: () => launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(location)}'),
                          mode: LaunchMode.externalApplication),
                      child: Text(location),
                    ),
                  if (link.isNotEmpty)
                    InfoRow(
                      icon: Icons.videocam_outlined,
                      label: 'ONLINE',
                      onTap: () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication),
                      child: Text(link, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.primary)),
                    ),
                  if (!cancelled && !past)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                      child: OutlinedButton.icon(
                        onPressed: () => launchUrl(Uri.parse(m['calendar_url'] as String), mode: LaunchMode.externalApplication),
                        icon: const Icon(Icons.edit_calendar_outlined),
                        label: const Text('Add to calendar'),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if ((m['agenda'] as String).isNotEmpty) ...[
            const SectionTitle('Agenda'),
            Appear(
              index: i++,
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(m['agenda'] as String, style: const TextStyle(height: 1.5, fontSize: 15)),
                ),
              ),
            ),
          ],
          if (m['has_minutes'] == true || (manage && (past || DateTime.now().isAfter(start)))) ...[
            SectionTitle('Minutes', trailing: manage ? SeeAll(label: m['has_minutes'] == true ? 'Edit' : 'Write', onTap: _minutes) : null),
            Appear(
              index: i++,
              child: Card(
                margin: EdgeInsets.zero,
                child: m['has_minutes'] == true
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SelectableText(m['minutes'] as String, style: const TextStyle(height: 1.5, fontSize: 15)),
                            const SizedBox(height: 10),
                            Text(
                              'By ${(m['minutes_by'] as Json?)?['name'] ?? '—'} · ${ago(m['minutes_at'] as String?)}',
                              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      )
                    : EmptyView('No minutes yet.', icon: Icons.description_outlined,
                        action: FilledButton.tonal(onPressed: _minutes, child: const Text('Write minutes'))),
              ),
            ),
          ],
          SectionTitle(
            'Invited · ${attendees.length}',
            trailing: manage ? SeeAll(label: 'Attendance', onTap: _attendance) : null,
          ),
          Appear(
            index: i++,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Pill('${counts['going']} going', tone: 'green'),
                  Pill('${counts['maybe']} maybe', tone: 'amber'),
                  Pill('${counts['declined']} can\'t', tone: 'red'),
                  Pill('${counts['pending']} no reply', tone: 'ghost'),
                ],
              ),
            ),
          ),
          Appear(
            index: i++,
            child: ListCard(
              children: [
                for (final a in attendees)
                  PersonTile(
                    a['member'] as Json,
                    trailing: (a['attendance'] as String).isNotEmpty
                        ? Pill(
                            switch (a['attendance']) { 'present' => 'Present', 'absent' => 'Absent', _ => 'Excused' },
                            tone: switch (a['attendance']) { 'present' => 'green', 'absent' => 'red', _ => 'ghost' },
                          )
                        : Pill(rsvpLabel(a['rsvp'] as String), tone: a['rsvp'] == 'pending' ? 'ghost' : rsvpTone(a['rsvp'] as String)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RsvpBar extends StatelessWidget {
  const _RsvpBar({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = [
      ('going', 'Going', Icons.check_circle_rounded, Tones.green(context)),
      ('maybe', 'Maybe', Icons.help_rounded, Tones.amber(context)),
      ('declined', 'Can\'t', Icons.cancel_rounded, Tones.red(context)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value == 'pending' ? 'Will you come?' : 'Your reply',
            style: TextStyle(fontWeight: FontWeight.w700, color: value == 'pending' ? cs.primary : cs.onSurfaceVariant)),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final it in items)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: GestureDetector(
                    onTap: () => onChanged(it.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      height: 52,
                      decoration: BoxDecoration(
                        color: value == it.$1 ? it.$4 : Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: value == it.$1 ? it.$4 : cs.outlineVariant),
                        boxShadow: value == it.$1
                            ? [BoxShadow(color: it.$4.withValues(alpha: .35), blurRadius: 12, offset: const Offset(0, 4))]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(it.$3, size: 20, color: value == it.$1 ? Colors.white : it.$4),
                          const SizedBox(width: 6),
                          Text(it.$2, style: TextStyle(fontWeight: FontWeight.w700, color: value == it.$1 ? Colors.white : cs.onSurface)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _MarkButton extends StatelessWidget {
  const _MarkButton({required this.icon, required this.kind, required this.on, required this.onTap});
  final IconData icon;
  final String kind;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = switch (kind) { 'present' => Tones.green(context), 'absent' => Tones.red(context), _ => cs.outline };
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: on ? color : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(color: on ? color : cs.outlineVariant),
        ),
        child: Icon(icon, size: 19, color: on ? Colors.white : color),
      ),
    );
  }
}

class _MinutesEditor extends StatefulWidget {
  const _MinutesEditor({required this.meeting});
  final Json meeting;
  @override
  State<_MinutesEditor> createState() => _MinutesEditorState();
}

class _MinutesEditorState extends State<_MinutesEditor> {
  late final _c = TextEditingController(text: widget.meeting['minutes'] as String);

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Minutes'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: BusyButton(
              label: 'Save',
              onPressed: () async {
                try {
                  await app.api!.post('meetings/${widget.meeting['id']}/minutes', {'minutes': _c.text});
                  app.changed();
                  if (context.mounted) Navigator.pop(context, true);
                } catch (e) {
                  if (context.mounted) showApiError(context, e);
                }
              },
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: TextField(
          controller: _c,
          autofocus: true,
          expands: true,
          maxLines: null,
          minLines: null,
          textAlignVertical: TextAlignVertical.top,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(height: 1.5, fontSize: 15.5),
          decoration: InputDecoration(
            hintText: 'Decisions, action points, who does what…\n\nTip: turn action points into tasks from the Tasks tab.',
            alignLabelWithHint: true,
            hintMaxLines: 4,
            fillColor: Theme.of(context).cardColor,
          ),
        ),
      ),
    );
  }
}

// ======================================================================= editor

class MeetingEditor extends StatefulWidget {
  const MeetingEditor({super.key, this.existing, this.committeeId});
  final Json? existing;
  final int? committeeId;
  @override
  State<MeetingEditor> createState() => _MeetingEditorState();
}

class _MeetingEditorState extends State<MeetingEditor> {
  late final _title = TextEditingController(text: widget.existing?['title'] as String?);
  late final _agenda = TextEditingController(text: widget.existing?['agenda'] as String?);
  late final _location = TextEditingController(text: widget.existing?['location'] as String?);
  late final _link = TextEditingController(text: widget.existing?['online_link'] as String?);
  int? _committee;
  DateTime? _start;
  DateTime? _end;
  ApiException? _error;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    final e = widget.existing;
    if (e != null) {
      _committee = (e['committee'] as Json?)?['id'] as int?;
      _start = DateTime.parse(e['start'] as String).toLocal();
      _end = e['end'] == null ? null : DateTime.parse(e['end'] as String).toLocal();
    } else {
      final mine = app.wingsFor('meetings');
      _committee = mine.contains(widget.committeeId)
          ? widget.committeeId
          : (!app.allWings('meetings') && mine.isNotEmpty ? mine.first : null);
      final now = DateTime.now();
      _start = DateTime(now.year, now.month, now.day + 1, 21);
    }
  }

  Future<void> _save() async {
    final app = AppScope.read(context);
    setState(() => _error = null);
    final body = {
      'title': _title.text,
      'agenda': _agenda.text,
      'start': _start == null ? null : isoDateTime(_start!),
      'end': _end == null ? null : isoDateTime(_end!),
      'location': _location.text,
      'online_link': _link.text,
    };
    try {
      final r = _editing
          ? await app.api!.patch('meetings/${widget.existing!['id']}', body)
          : await app.api!.post('meetings', {...body, 'committee': _committee});
      app.changed();
      if (mounted) {
        toast(context, _editing ? 'Saved · invitees were told about changes' : 'Meeting scheduled · invitations sent');
        Navigator.pop(context, r['meeting']);
      }
    } on ApiException catch (e) {
      setState(() => _error = e);
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit meeting' : 'New meeting')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            controller: _title,
            autofocus: !_editing,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            decoration: InputDecoration(labelText: 'Title', hintText: 'e.g. Weekly committee meeting', errorText: fieldError(_error, 'title')),
          ),
          if (!_editing) ...[
            const SizedBox(height: 12),
            CommitteeField(
              label: 'Who is invited',
              committees: app.committeesFor('meetings'),
              value: _committee,
              noneLabel: app.allWings('meetings') ? 'General meeting · every member' : null,
              onChanged: (v) => setState(() => _committee = v),
            ),
          ],
          const SizedBox(height: 12),
          DateField(
            label: 'Starts',
            withTime: true,
            allowClear: false,
            value: _start,
            onChanged: (v) => setState(() {
              if (v == null) return;
              final shift = _end != null && _start != null ? _end!.difference(_start!) : null;
              _start = v;
              if (shift != null) _end = v.add(shift);
            }),
          ),
          if (fieldError(_error, 'start') != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Text(fieldError(_error, 'start')!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
            ),
          const SizedBox(height: 12),
          DateField(label: 'Ends (optional)', withTime: true, value: _end, onChanged: (v) => setState(() => _end = v)),
          if (_start != null && _end == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final d in const [30, 60, 90, 120])
                    ActionChip(
                      label: Text(d < 60 ? '$d min' : '${d / 60 == (d ~/ 60) ? d ~/ 60 : (d / 60).toStringAsFixed(1)} h'),
                      onPressed: () => setState(() => _end = _start!.add(Duration(minutes: d))),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _location,
            decoration: const InputDecoration(labelText: 'Place (optional)', prefixIcon: Icon(Icons.place_outlined)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _link,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'Online link (optional)',
              hintText: 'https://meet.google.com/…',
              prefixIcon: const Icon(Icons.videocam_outlined),
              errorText: fieldError(_error, 'online_link'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _agenda,
            minLines: 4,
            maxLines: 10,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Agenda (optional)', alignLabelWithHint: true, hintText: '1. …\n2. …'),
          ),
          const SizedBox(height: 26),
          BusyButton(label: _editing ? 'Save' : 'Schedule & invite', icon: Icons.send_rounded, onPressed: _save),
        ],
      ),
    );
  }
}
