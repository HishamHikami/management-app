import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../api.dart';
import '../state.dart';
import '../ui.dart';
import 'home.dart';

Future<void> openNewTask(BuildContext context, {int? committeeId}) async {
  final created = await push<Json>(context, TaskEditor(committeeId: committeeId));
  if (created != null && context.mounted) {
    push(context, TaskDetailScreen(id: created['id'] as int));
  }
}

// ======================================================================= list

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key, this.initialScope, this.standalone = false, this.committeeId, this.title});
  final String? initialScope;
  final Widget? title;
  final bool standalone;
  final int? committeeId;
  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  late String _scope = widget.initialScope ?? 'team';
  String _status = 'open';
  int? _committee;
  String _q = '';
  bool _searching = false;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _committee = widget.committeeId;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final scopes = <(String, String)>[
      ('mine', 'Mine'),
      ('team', 'My wings'),
      if (app.allWings('tasks')) ('all', 'All'),
    ];
    if (!scopes.any((s) => s.$1 == _scope)) _scope = 'team';
    return Scaffold(
      appBar: AppBar(
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _searching
              ? TextField(
                  key: const ValueKey('s'),
                  controller: _search,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Search tasks',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    filled: false,
                  ),
                  onSubmitted: (v) => setState(() => _q = v.trim()),
                )
              : (widget.title ?? const Text('Tasks', key: ValueKey('t'))),
        ),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _search.clear();
                _q = '';
              }
            }),
          ),
          if (!widget.standalone) ...appBarActions(context),
        ],
      ),
      floatingActionButton: app.can('tasks') && app.wingsFor('tasks').isNotEmpty
          ? FloatingActionButton(
              heroTag: 'task-fab',
              tooltip: 'New task',
              onPressed: () => openNewTask(context, committeeId: _committee),
              child: const Icon(Icons.add_rounded),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Segments<String>(items: scopes, value: _scope, onChanged: (v) => setState(() => _scope = v)),
          ),
          ChipRow(
            children: [
              for (final s in const [('open', 'Open'), ('closed', 'Done')])
                ChoiceChip(
                  label: Text(s.$2),
                  selected: _status == s.$1,
                  showCheckmark: false,
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    setState(() => _status = s.$1);
                  },
                ),
              Container(width: 1, height: 22, color: Theme.of(context).colorScheme.outlineVariant),
              _CommitteeMenuChip(
                value: _committee,
                onChanged: (v) => setState(() => _committee = v),
              ),
            ],
          ),
          Expanded(
            child: Loader(
              key: ValueKey('tasks-$_scope-$_status-$_committee-$_q'),
              load: () => app.api!.get('tasks', query: {
                'scope': _scope,
                'status': _status,
                'committee': _committee?.toString() ?? '',
                'q': _q,
              }),
              builder: (context, d, reload) => _TaskList(
                tasks: (d['tasks'] as List).cast<Json>(),
                closed: _status == 'closed',
                reload: reload,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommitteeMenuChip extends StatelessWidget {
  const _CommitteeMenuChip({required this.value, required this.onChanged});
  final int? value;
  final ValueChanged<int?> onChanged;
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = app.committee(value);
    return ActionChip(
      avatar: c == null ? const Icon(Icons.filter_list_rounded, size: 18) : Dot(colorOf(context, c)),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(c == null ? 'All wings' : c['name'] as String),
          const Icon(Icons.arrow_drop_down_rounded, size: 20),
        ],
      ),
      onPressed: () async {
        final r = await showPicker<int?>(
          context,
          title: 'Wing',
          selected: value,
          groups: [
            PickGroup([
              const PickOption<int?>(null, 'All wings', icon: Icons.all_inclusive_rounded),
              for (final c in app.committees)
                PickOption<int?>(c['id'] as int, c['name'] as String, color: colorOf(context, c)),
            ]),
          ],
        );
        if (r != null) onChanged(r.value);
      },
    );
  }
}

class _TaskList extends StatelessWidget {
  const _TaskList({required this.tasks, required this.closed, required this.reload});
  final List<Json> tasks;
  final bool closed;
  final Future<void> Function() reload;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return RefreshList(
        onRefresh: reload,
        children: [
          EmptyView(closed ? 'No finished tasks here yet.' : 'No open tasks. Nice work!', icon: Icons.task_alt_rounded),
        ],
      );
    }
    final groups = <String, List<Json>>{};
    if (closed) {
      groups['Finished'] = tasks;
    } else {
      final today = DateUtils.dateOnly(DateTime.now());
      for (final t in tasks) {
        final due = t['due_date'] == null ? null : DateTime.parse(t['due_date'] as String);
        final key = t['is_overdue'] == true
            ? 'Overdue'
            : due == null
            ? 'No due date'
            : due.difference(today).inDays <= 7
            ? 'This week'
            : 'Later';
        groups.putIfAbsent(key, () => []).add(t);
      }
    }
    const order = ['Overdue', 'This week', 'Later', 'No due date', 'Finished'];
    var i = 0;
    return RefreshList(
      onRefresh: reload,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      children: [
        for (final g in order)
          if (groups[g] != null) ...[
            SectionTitle(g, trailing: Pill('${groups[g]!.length}', tone: g == 'Overdue' ? 'red' : 'neutral')),
            Appear(
              index: i++,
              child: ListCard(
                children: [
                  for (final t in groups[g]!)
                    TaskTile(t, onTap: () => push(context, TaskDetailScreen(id: t['id'] as int))),
                ],
              ),
            ),
          ],
      ],
    );
  }
}

// ======================================================================= detail

class TaskDetailScreen extends StatelessWidget {
  const TaskDetailScreen({super.key, required this.id});
  final int id;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Loader(
      load: () => app.api!.get('tasks/$id'),
      builder: (context, d, reload) => _TaskPage(t: d['task'] as Json, reload: reload),
    );
  }
}

class _TaskPage extends StatefulWidget {
  const _TaskPage({required this.t, required this.reload});
  final Json t;
  final Future<void> Function() reload;
  @override
  State<_TaskPage> createState() => _TaskPageState();
}

class _TaskPageState extends State<_TaskPage> {
  final _comment = TextEditingController();
  bool _sending = false;
  late Json t = widget.t;

  @override
  void didUpdateWidget(_TaskPage old) {
    super.didUpdateWidget(old);
    t = widget.t;
  }

  AppState get app => AppScope.read(context);

  Future<void> _post(String path, Json body, {String? done}) async {
    try {
      final r = await app.api!.post('tasks/${t['id']}/$path', body);
      setState(() => t = r['task'] as Json);
      app.changed();
      if (done != null && mounted) toast(context, done);
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _setStatus(String status) async {
    if (status == t['status']) return;
    HapticFeedback.mediumImpact();
    await _post('status', {'status': status}, done: status == 'done' ? 'Marked as done 🎉' : null);
  }

  Future<void> _statusWithNote() async {
    String status = t['status'] as String;
    final note = TextEditingController();
    final ok = await showSheet<bool>(
      context,
      title: 'Update status',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PickerField<String>(
              label: 'Status',
              value: status,
              groups: [
                PickGroup([
                  for (final s in app.choice('statuses'))
                    PickOption(s['value'] as String, s['label'] as String, icon: statusIcon(s['value'] as String)),
                ]),
              ],
              onChanged: (v) => set(() => status = v ?? status),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Note (optional)', hintText: 'What happened?'),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok == true) await _post('status', {'status': status, 'note': note.text});
  }

  Future<void> _send() async {
    final text = _comment.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    await _post('comments', {'body': text});
    if (mounted) {
      _comment.clear();
      setState(() => _sending = false);
      FocusScope.of(context).unfocus();
    }
  }

  Future<void> _reassign() async {
    final committees = app.committeesFor('tasks');
    int committee = (t['committee'] as Json)['id'] as int;
    Set<int> people = (t['assignees'] as List).map((a) => (a as Json)['id'] as int).toSet();
    final note = TextEditingController();
    final ok = await showSheet<bool>(
      context,
      title: 'Reassign',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CommitteeField(
              committees: committees.any((c) => c['id'] == committee) ? committees : [t['committee'] as Json, ...committees],
              value: committee,
              onChanged: (v) => set(() {
                if (v != null && v != committee) {
                  committee = v;
                  people = {};
                }
              }),
            ),
            const SizedBox(height: 12),
            PeopleField(
              label: 'Assigned to',
              people: assignablePeople(app, committee),
              value: people,
              placeholder: 'The whole wing',
              onChanged: (v) => set(() => people = v),
            ),
            const SizedBox(height: 12),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (optional)')),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reassign')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _post('assign', {'committee': committee, 'assignees': people.toList(), 'note': note.text}, done: 'Reassigned');
    }
  }

  Future<void> _menu() async {
    final r = await showActions(
      context,
      title: 'Task',
      actions: [
        const PickOption('edit', 'Edit details', icon: Icons.edit_outlined),
        const PickOption('assign', 'Reassign', icon: Icons.swap_horiz_rounded),
        if (t['status'] != 'cancelled') const PickOption('cancel', 'Cancel task', icon: Icons.block_rounded),
        const PickOption('delete', 'Delete', icon: Icons.delete_outline_rounded, danger: true),
      ],
    );
    if (!mounted) return;
    switch (r) {
      case 'edit':
        final saved = await push<Json>(context, TaskEditor(task: t));
        if (saved != null) widget.reload();
      case 'assign':
        _reassign();
      case 'cancel':
        _setStatus('cancelled');
      case 'delete':
        if (await confirm(context, title: 'Delete this task?', message: 'Its timeline will be deleted too.', action: 'Delete', danger: true)) {
          try {
            await app.api!.delete('tasks/${t['id']}');
            app.changed();
            if (mounted) Navigator.pop(context);
          } catch (e) {
            if (mounted) showApiError(context, e);
          }
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final assignees = (t['assignees'] as List).cast<Json>();
    final timeline = (t['timeline'] as List).cast<Json>();
    final canWork = t['can_work'] == true;
    final pri = t['priority'] as int;
    return Scaffold(
      appBar: AppBar(
        actions: [
          if (canWork) IconButton(tooltip: 'Status with note', icon: const Icon(Icons.edit_note_rounded), onPressed: _statusWithNote),
          if (t['can_manage'] == true) IconButton(icon: const Icon(Icons.more_vert_rounded), onPressed: _menu),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshList(
              onRefresh: widget.reload,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                Appear(
                  index: 0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          CommitteeChip(t['committee'] as Json),
                          if (pri >= 3) Pill(t['priority_label'] as String, tone: priorityTone(pri), icon: Icons.flag_rounded),
                          if (t['pill'] != null) Pill((t['pill'] as Json)['label'] as String, tone: (t['pill'] as Json)['tone'] as String),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        t['title'] as String,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Appear(
                  index: 1,
                  child: _StatusStepper(status: t['status'] as String, enabled: canWork, onChanged: _setStatus),
                ),
                const SizedBox(height: 14),
                Appear(
                  index: 2,
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Column(
                      children: [
                        InfoRow(
                          icon: Icons.person_outline_rounded,
                          label: 'ASSIGNED TO',
                          onTap: t['can_manage'] == true ? _reassign : null,
                          child: assignees.isEmpty
                              ? Text('The whole ${(t['committee'] as Json)['name']} wing')
                              : Wrap(
                                  spacing: 10,
                                  runSpacing: 6,
                                  children: [
                                    for (final a in assignees)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [Initials(a['name'] as String, radius: 11), const SizedBox(width: 6), Text(a['name'] as String)],
                                      ),
                                  ],
                                ),
                        ),
                        InfoRow(
                          icon: Icons.event_outlined,
                          label: 'DUE',
                          child: Text(
                            t['due_date'] == null ? 'No due date' : fmtDate(t['due_date'] as String),
                            style: TextStyle(color: t['is_overdue'] == true ? Tones.red(context) : null),
                          ),
                        ),
                        if (t['created_by'] != null)
                          InfoRow(
                            icon: Icons.outlined_flag_rounded,
                            label: 'CREATED BY',
                            child: Text('${(t['created_by'] as Json)['name']} · ${ago(t['created_at'] as String?)}'),
                          ),
                      ],
                    ),
                  ),
                ),
                if ((t['description'] as String).isNotEmpty) ...[
                  const SectionTitle('Details'),
                  Appear(
                    index: 3,
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SelectableText(t['description'] as String, style: const TextStyle(height: 1.45, fontSize: 15)),
                      ),
                    ),
                  ),
                ],
                const SectionTitle('Activity'),
                Appear(index: 4, child: _Timeline(items: timeline)),
              ],
            ),
          ),
          if (canWork)
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: .6))),
              ),
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _comment,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: 'Write an update…',
                          filled: true,
                          fillColor: cs.surfaceContainerHighest.withValues(alpha: .6),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filled(
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

IconData statusIcon(String s) => switch (s) {
  'doing' => Icons.play_circle_outline_rounded,
  'waiting' => Icons.hourglass_top_rounded,
  'done' => Icons.check_circle_outline_rounded,
  'cancelled' => Icons.block_rounded,
  _ => Icons.radio_button_unchecked_rounded,
};

/// To do → In progress → Waiting → Done, tap a step to move there.
class _StatusStepper extends StatelessWidget {
  const _StatusStepper({required this.status, required this.enabled, required this.onChanged});
  final String status;
  final bool enabled;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const steps = [('todo', 'To do'), ('doing', 'In progress'), ('waiting', 'Waiting'), ('done', 'Done')];
    if (status == 'cancelled') {
      return Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: Icon(Icons.block_rounded, color: cs.outline),
          title: const Text('Cancelled'),
          trailing: enabled ? TextButton(onPressed: () => onChanged('todo'), child: const Text('Reopen')) : null,
        ),
      );
    }
    final current = steps.indexWhere((s) => s.$1 == status);
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .6), borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          for (var i = 0; i < steps.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: enabled ? () => onChanged(steps[i].$1) : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  height: 44,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: i == current
                        ? (steps[i].$1 == 'done' ? Tones.green(context) : cs.primary)
                        : i < current
                        ? cs.primaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: i == current
                          ? Colors.white
                          : i < current
                          ? cs.onPrimaryContainer
                          : cs.onSurfaceVariant,
                    ),
                    child: Text(steps[i].$2, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.items});
  final List<Json> items;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = items.reversed.toList();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 30,
                      child: Column(
                        children: [
                          _TimelineIcon(kind: rows[i]['kind'] as String),
                          if (i < rows.length - 1)
                            Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 4), color: cs.outlineVariant.withValues(alpha: .6))),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 16), child: _TimelineBody(u: rows[i]))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TimelineIcon extends StatelessWidget {
  const _TimelineIcon({required this.kind});
  final String kind;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (icon, color) = switch (kind) {
      'created' => (Icons.add_rounded, cs.primary),
      'status' => (Icons.sync_alt_rounded, Tones.blue(context)),
      'assign' => (Icons.swap_horiz_rounded, Tones.amber(context)),
      'edit' => (Icons.edit_outlined, cs.outline),
      _ => (Icons.chat_bubble_outline_rounded, Tones.green(context)),
    };
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(color: color.withValues(alpha: .14), shape: BoxShape.circle),
      child: Icon(icon, size: 16, color: color),
    );
  }
}

class _TimelineBody extends StatelessWidget {
  const _TimelineBody({required this.u});
  final Json u;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final who = (u['author'] as Json?)?['name'] as String? ?? 'Someone';
    final kind = u['kind'] as String;
    final headline = switch (kind) {
      'created' => 'created the task${(u['to'] as String).isNotEmpty ? ' for ${u['to']}' : ''}',
      'status' => 'moved it from ${u['from']} to ${u['to']}',
      'assign' => 'reassigned it to ${u['to']}',
      'edit' => 'changed the details',
      _ => '',
    };
    final body = u['body'] as String;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 5),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: who, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (headline.isNotEmpty) TextSpan(text: ' $headline'),
              TextSpan(text: '  ·  ${ago(u['at'] as String?)}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
            ],
          ),
          style: const TextStyle(fontSize: 14),
        ),
        if (body.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: .6),
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(14),
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(14),
                topLeft: Radius.circular(4),
              ),
            ),
            child: SelectableText(body, style: const TextStyle(height: 1.4)),
          ),
        ],
      ],
    );
  }
}

// ======================================================================= editor

/// People who can be assigned for a committee: everyone for the core
/// committee (the committee's own members first), only its members for heads.
List<Json> assignablePeople(AppState app, int? committee) {
  final inC = app.members.where((m) => ((m['committee_ids'] as List?) ?? []).contains(committee)).toList();
  if (!app.allWings('tasks')) return inC;
  final rest = app.members.where((m) => !inC.contains(m)).toList();
  return [...inC, ...rest];
}

class TaskEditor extends StatefulWidget {
  const TaskEditor({super.key, this.task, this.committeeId});
  final Json? task;
  final int? committeeId;
  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  late final _title = TextEditingController(text: widget.task?['title'] as String?);
  late final _desc = TextEditingController(text: widget.task?['description'] as String?);
  int? _committee;
  Set<int> _people = {};
  int _priority = 2;
  DateTime? _due;
  ApiException? _error;

  bool get _editing => widget.task != null;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    final app = AppScope.read(context);
    if (t != null) {
      _committee = (t['committee'] as Json)['id'] as int;
      _priority = t['priority'] as int;
      _due = t['due_date'] == null ? null : DateTime.parse(t['due_date'] as String);
    } else {
      final ids = app.wingsFor('tasks');
      _committee = ids.contains(widget.committeeId)
          ? widget.committeeId
          : ids.isNotEmpty && !app.allWings('tasks')
          ? ids.first
          : null;
    }
  }

  Future<void> _save() async {
    final app = AppScope.read(context);
    setState(() => _error = null);
    try {
      Json r;
      if (_editing) {
        r = await app.api!.patch('tasks/${widget.task!['id']}', {
          'title': _title.text,
          'description': _desc.text,
          'priority': _priority,
          'due_date': _due == null ? null : isoDate(_due!),
        });
      } else {
        r = await app.api!.post('tasks', {
          'title': _title.text,
          'description': _desc.text,
          'committee': _committee,
          'assignees': _people.toList(),
          'priority': _priority,
          'due_date': _due == null ? null : isoDate(_due!),
        });
      }
      app.changed();
      if (mounted) {
        toast(context, _editing ? 'Saved' : 'Task created');
        Navigator.pop(context, r['task']);
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
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit task' : 'New task')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            controller: _title,
            autofocus: !_editing,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            decoration: InputDecoration(labelText: 'What needs to be done?', errorText: fieldError(_error, 'title')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Details (optional)', alignLabelWithHint: true),
          ),
          if (!_editing) ...[
            const SizedBox(height: 12),
            CommitteeField(
              committees: app.committeesFor('tasks'),
              value: _committee,
              onChanged: (v) => setState(() {
                _committee = v;
                _people = {};
              }),
            ),
            if (fieldError(_error, 'committee') != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Text(fieldError(_error, 'committee')!, style: TextStyle(color: cs.error, fontSize: 12)),
              ),
            const SizedBox(height: 12),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _committee == null ? .5 : 1,
              child: IgnorePointer(
                ignoring: _committee == null,
                child: PeopleField(
                  label: 'Assign to',
                  people: assignablePeople(app, _committee),
                  value: _people,
                  placeholder: 'The whole wing',
                  onChanged: (v) => setState(() => _people = v),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          DateField(label: 'Due date (optional)', value: _due, onChanged: (v) => setState(() => _due = v)),
          const SizedBox(height: 18),
          Text('Priority', style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Segments<int>(
            items: [for (final p in app.choice('priorities')) (p['value'] as int, p['label'] as String)],
            value: _priority,
            onChanged: (v) => setState(() => _priority = v),
          ),
          const SizedBox(height: 28),
          BusyButton(label: _editing ? 'Save' : 'Create task', icon: Icons.check_rounded, onPressed: _save),
        ],
      ),
    );
  }
}
