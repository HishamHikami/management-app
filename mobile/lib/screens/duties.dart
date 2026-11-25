import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../api.dart';
import '../state.dart';
import '../ui.dart';
import 'home.dart';
import 'tasks.dart';

/// The Tasks tab: one-time tasks and recurring duties (responsibilities), switched at the top.
class WorkTab extends StatefulWidget {
  const WorkTab({super.key});
  @override
  State<WorkTab> createState() => _WorkTabState();
}

class _WorkTabState extends State<WorkTab> {
  bool _duties = false;
  @override
  Widget build(BuildContext context) {
    final switcher = SizedBox(
      width: 220,
      child: Segments<bool>(
        items: const [(false, 'Tasks'), (true, 'Duties')],
        value: _duties,
        onChanged: (v) => setState(() => _duties = v),
      ),
    );
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: _duties
          ? DutiesScreen(key: const ValueKey('d'), title: switcher)
          : TasksScreen(key: const ValueKey('t'), title: switcher),
    );
  }
}

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

String repeatText(Json r) {
  switch (r['repeat']) {
    case 'daily':
      return 'Every day';
    case 'weekly':
      final w = r['weekday'] as int?;
      return w == null ? 'Every week' : 'Every ${_weekdays[w]}';
    case 'monthly':
      final d = r['monthday'] as int?;
      return d == null ? 'Every month' : 'Monthly on day $d';
    default:
      return 'Once';
  }
}

String dueText(Json r) {
  if (r['due_today'] == true) return 'Due today';
  if (r['due'] != null) return 'Due ${DateFormat('EEE d MMM').format(DateTime.parse(r['due'] as String))}';
  if (r['next'] != null) return 'Next ${DateFormat('EEE d MMM').format(DateTime.parse(r['next'] as String))}';
  return 'Nothing coming up';
}

class DutiesScreen extends StatefulWidget {
  const DutiesScreen({super.key, this.title});
  final Widget? title;
  @override
  State<DutiesScreen> createState() => _DutiesScreenState();
}

class _DutiesScreenState extends State<DutiesScreen> {
  String _scope = 'mine';
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: widget.title ?? const Text('Duties'), actions: appBarActions(context)),
      floatingActionButton: app.wingsFor('responsibilities').isNotEmpty
          ? FloatingActionButton(
              heroTag: 'duty-fab',
              tooltip: 'New responsibility',
              onPressed: () => push(context, const ResponsibilityEditor()),
              child: const Icon(Icons.add_rounded),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Segments<String>(
              items: const [('mine', 'Mine'), ('all', 'My wings')],
              value: _scope,
              onChanged: (v) => setState(() => _scope = v),
            ),
          ),
          Expanded(
            child: Loader(
              key: ValueKey('duties-$_scope'),
              load: () => app.api!.get('responsibilities', query: {'scope': _scope}),
              builder: (context, d, reload) {
                final items = (d['responsibilities'] as List).cast<Json>();
                items.sort((a, b) => (b['due'] != null ? 1 : 0).compareTo(a['due'] != null ? 1 : 0));
                return RefreshList(
                  onRefresh: reload,
                  children: [
                    if (items.isEmpty)
                      EmptyView(_scope == 'mine' ? 'You have no regular duties yet.' : 'No duties in your wings yet.',
                          icon: Icons.event_repeat_outlined),
                    if (items.isNotEmpty)
                      Appear(index: 0, child: ListCard(children: [for (final r in items) DutyTile(r: r, showHolder: _scope != 'mine')])),
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

/// A duty row with a tick button when something is due.
class DutyTile extends StatelessWidget {
  const DutyTile({super.key, required this.r, this.showHolder = false});
  final Json r;
  final bool showHolder;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final due = r['due'] != null;
    final missed = (r['missed'] as int?) ?? 0;
    final canTick = due && (r['is_mine'] == true || r['can_manage'] == true);
    return Pressable(
      borderRadius: 0,
      onTap: () => push(context, ResponsibilityDetailScreen(id: r['id'] as int)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: (due ? gold : cs.primary).withValues(alpha: .16), borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.event_repeat_rounded, color: due ? const Color(0xFF8A6100) : cs.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r['title'] as String, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Pill(dueText(r), tone: r['due_today'] == true ? 'amber' : due ? 'red' : 'neutral'),
                      if (missed > 0) ...[const SizedBox(width: 6), Pill('$missed missed', tone: 'red')],
                      const SizedBox(width: 8),
                      Expanded(child: Meta([repeatText(r), if (showHolder) ((r['holder'] as Json?)?['name'] as String? ?? '')])),
                    ],
                  ),
                ],
              ),
            ),
            if (canTick)
              IconButton(
                tooltip: 'Mark done',
                icon: Icon(Icons.check_circle_outline_rounded, color: Tones.green(context), size: 28),
                onPressed: () async {
                  HapticFeedback.mediumImpact();
                  try {
                    await app.api!.post('responsibilities/${r['id']}/done', {});
                    app.changed();
                    if (context.mounted) toast(context, 'Done ✓');
                  } catch (e) {
                    if (context.mounted) showApiError(context, e);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}

class ResponsibilityDetailScreen extends StatelessWidget {
  const ResponsibilityDetailScreen({super.key, required this.id});
  final int id;
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Loader(
      load: () => app.api!.get('responsibilities/$id'),
      builder: (context, d, reload) => _DutyPage(r: d['responsibility'] as Json, reload: reload),
    );
  }
}

class _DutyPage extends StatelessWidget {
  const _DutyPage({required this.r, required this.reload});
  final Json r;
  final Future<void> Function() reload;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final mine = r['is_mine'] == true;
    final manage = r['can_manage'] == true;
    final history = ((r['history'] as List?) ?? []).cast<Json>();
    final note = TextEditingController();

    Future<void> setSchedule() async {
      final changed = await push<bool>(context, _ScheduleEditor(r: r));
      if (changed == true) reload();
    }

    return Scaffold(
      appBar: AppBar(actions: [
        if (manage)
          IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () async {
            await push(context, ResponsibilityEditor(existing: r));
            reload();
          }),
      ]),
      body: RefreshList(
        onRefresh: reload,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
        children: [
          if (r['committee'] != null) Align(alignment: Alignment.centerLeft, child: CommitteeChip(r['committee'] as Json)),
          const SizedBox(height: 10),
          Text(r['title'] as String, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          if ((r['description'] as String).isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(r['description'] as String, style: TextStyle(color: cs.onSurfaceVariant, height: 1.45)),
          ],
          const SizedBox(height: 14),
          Card(
            margin: EdgeInsets.zero,
            child: Column(children: [
              InfoRow(icon: Icons.person_outline_rounded, label: 'HELD BY', child: Text((r['holder'] as Json)['name'] as String)),
              InfoRow(icon: Icons.event_repeat_rounded, label: 'REPEATS', onTap: (mine || manage) ? setSchedule : null,
                  child: Text(repeatText(r))),
              InfoRow(icon: Icons.notifications_active_outlined, label: 'REMINDER', onTap: (mine || manage) ? setSchedule : null,
                  child: Text(switch (r['remind']) { 'same_day' => 'Morning of the day', 'day_before' => 'The day before', _ => 'No reminder' })),
              InfoRow(icon: Icons.flag_outlined, label: 'STATUS', child: Text(dueText(r))),
            ]),
          ),
          if (mine || manage) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(onPressed: setSchedule, icon: const Icon(Icons.tune_rounded), label: const Text('Set how often & reminder')),
          ],
          if (r['due'] != null && (mine || manage)) ...[
            const SizedBox(height: 16),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (optional)')),
            const SizedBox(height: 10),
            BusyButton(
              label: r['due_today'] == true ? 'Done for today' : 'Mark ${dueText(r).replaceFirst('Due ', '')} as done',
              icon: Icons.check_rounded,
              onPressed: () async {
                try {
                  await app.api!.post('responsibilities/${r['id']}/done', {'date': r['due'], 'note': note.text});
                  app.changed();
                  await reload();
                } catch (e) {
                  if (context.mounted) showApiError(context, e);
                }
              },
            ),
          ],
          SectionTitle('History', trailing: (r['missed'] as int) > 0 ? Pill('${r['missed']} missed (30 days)', tone: 'red') : null),
          if (history.isEmpty)
            const Card(margin: EdgeInsets.zero, child: EmptyView('Nothing ticked off yet.', icon: Icons.history_rounded))
          else
            ListCard(children: [
              for (final h in history)
                ListTile(
                  leading: Icon(Icons.check_circle_rounded, color: Tones.green(context)),
                  title: Text(DateFormat('EEE d MMM yyyy').format(DateTime.parse(h['date'] as String))),
                  subtitle: Text([((h['by'] as Json?)?['name'] as String?) ?? '', h['note'] as String].where((x) => x.isNotEmpty).join(' · ')),
                ),
            ]),
        ],
      ),
    );
  }
}

/// The holder decides how often the duty repeats and when to be reminded.
class _ScheduleEditor extends StatefulWidget {
  const _ScheduleEditor({required this.r});
  final Json r;
  @override
  State<_ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<_ScheduleEditor> {
  late String _repeat = widget.r['repeat'] as String;
  late int _weekday = (widget.r['weekday'] as int?) ?? DateTime.now().weekday - 1;
  late int _monthday = (widget.r['monthday'] as int?) ?? DateTime.now().day;
  late String _remind = widget.r['remind'] as String;
  late DateTime _start = DateTime.parse(widget.r['start_date'] as String);

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('How often & reminder')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text('Repeats', style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Segments<String>(
            items: const [('daily', 'Daily'), ('weekly', 'Weekly'), ('monthly', 'Monthly'), ('once', 'Once')],
            value: _repeat,
            onChanged: (v) => setState(() => _repeat = v),
          ),
          const SizedBox(height: 14),
          if (_repeat == 'weekly')
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (var i = 0; i < 7; i++)
                ChoiceChip(label: Text(_weekdays[i].substring(0, 3)), selected: _weekday == i, showCheckmark: false,
                    onSelected: (_) => setState(() => _weekday = i)),
            ]),
          if (_repeat == 'monthly')
            PickerField<int>(
              label: 'Day of the month',
              value: _monthday,
              groups: [PickGroup([for (var d = 1; d <= 31; d++) PickOption(d, '$d')])],
              onChanged: (v) => setState(() => _monthday = v ?? _monthday),
            ),
          if (_repeat == 'once' || _repeat == 'daily')
            DateField(label: _repeat == 'once' ? 'On' : 'Starting', value: _start, allowClear: false,
                onChanged: (v) => setState(() => _start = v ?? _start)),
          const SizedBox(height: 22),
          Text('Remind me', style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Segments<String>(
            items: const [('same_day', 'That morning'), ('day_before', 'Day before'), ('none', 'Never')],
            value: _remind,
            onChanged: (v) => setState(() => _remind = v),
          ),
          const SizedBox(height: 28),
          BusyButton(label: 'Save', icon: Icons.check_rounded, onPressed: () async {
            final nav = Navigator.of(context);
            try {
              await app.api!.patch('responsibilities/${widget.r['id']}', {
                'repeat': _repeat,
                'weekday': _repeat == 'weekly' ? _weekday : null,
                'monthday': _repeat == 'monthly' ? _monthday : null,
                'start_date': isoDate(_start),
                'remind': _remind,
              });
              app.changed();
              nav.pop(true);
            } catch (e) {
              if (context.mounted) showApiError(context, e);
            }
          }),
        ],
      ),
    );
  }
}

/// Create / edit a responsibility (people with the responsibilities permission).
class ResponsibilityEditor extends StatefulWidget {
  const ResponsibilityEditor({super.key, this.existing, this.committeeId});
  final Json? existing;
  final int? committeeId;
  @override
  State<ResponsibilityEditor> createState() => _ResponsibilityEditorState();
}

class _ResponsibilityEditorState extends State<ResponsibilityEditor> {
  late final _title = TextEditingController(text: widget.existing?['title'] as String?);
  late final _desc = TextEditingController(text: widget.existing?['description'] as String?);
  int? _committee;
  int? _holder;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final app = AppScope.read(context);
    _committee = (e?['committee'] as Json?)?['id'] as int? ??
        (app.wingsFor('responsibilities').contains(widget.committeeId) ? widget.committeeId : null);
    _holder = (e?['holder'] as Json?)?['id'] as int?;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final editing = widget.existing != null;
    final people = app.allWings('responsibilities')
        ? app.members
        : app.members.where((m) => ((m['committee_ids'] as List?) ?? []).contains(_committee)).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit responsibility' : 'New responsibility'),
        actions: [
          if (editing)
            IconButton(icon: const Icon(Icons.delete_outline_rounded), onPressed: () async {
              final nav = Navigator.of(context);
              if (!await confirm(context, title: 'Delete this responsibility?', message: 'Its history is deleted too.', action: 'Delete', danger: true)) return;
              await app.api!.delete('responsibilities/${widget.existing!['id']}');
              app.changed();
              nav.pop();
              if (nav.canPop()) nav.pop();
            }),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(controller: _title, textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: 'Responsibility', hintText: 'e.g. Open the hall before class', errorText: fieldError(_error, 'title'))),
          const SizedBox(height: 12),
          TextField(controller: _desc, minLines: 2, maxLines: 6, textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Details (optional)', alignLabelWithHint: true)),
          const SizedBox(height: 12),
          CommitteeField(
            label: 'Wing',
            committees: app.committeesFor('responsibilities'),
            value: _committee,
            noneLabel: app.allWings('responsibilities') ? 'No wing (unit-wide)' : null,
            onChanged: (v) => setState(() => _committee = v),
          ),
          const SizedBox(height: 12),
          PickerField<int?>(
            label: 'Held by',
            value: _holder,
            placeholder: 'Choose a person',
            searchable: people.length > 8,
            groups: [PickGroup([for (final m in people) PickOption<int?>(m['id'] as int, m['name'] as String, leading: Initials(m['name'] as String))])],
            onChanged: (v) => setState(() => _holder = v),
          ),
          if (fieldError(_error, 'holder') != null)
            Padding(padding: const EdgeInsets.only(left: 12, top: 4), child: Text(fieldError(_error, 'holder')!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12))),
          const SizedBox(height: 10),
          Text('The person who holds it chooses how often it repeats and their reminder.',
              style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 24),
          BusyButton(label: editing ? 'Save' : 'Create', icon: Icons.check_rounded, onPressed: () async {
            setState(() => _error = null);
            final body = {'title': _title.text, 'description': _desc.text, 'committee': _committee, 'holder': _holder};
            final nav = Navigator.of(context);
            try {
              editing
                  ? await app.api!.patch('responsibilities/${widget.existing!['id']}', body)
                  : await app.api!.post('responsibilities', body);
              app.changed();
              nav.pop();
            } on ApiException catch (e) {
              setState(() => _error = e);
              if (context.mounted) showApiError(context, e);
            }
          }),
        ],
      ),
    );
  }
}
