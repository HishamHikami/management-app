import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'picker.dart';
import 'state.dart';

export 'picker.dart';

// ---------------------------------------------------------------- colors & text

/// Navy and gold from the association's logo. Change them here to rebrand the app.
const brand = Color(0xFF0B2A60);
const gold = Color(0xFFF0C452);

/// Navy gradient for hero cards.
const brandGradient = [Color(0xFF1A4A96), brand, Color(0xFF041A45)];
const brandGradientDark = [Color(0xFF123A7A), Color(0xFF06183D)];

Color committeeColor(String? name, Brightness b) {
  final dark = b == Brightness.dark;
  switch (name) {
    case 'blue':
      return dark ? const Color(0xFF86B4EE) : const Color(0xFF2F6FB5);
    case 'indigo':
      return dark ? const Color(0xFF9FA8F5) : const Color(0xFF4651B8);
    case 'purple':
      return dark ? const Color(0xFFB9A2F2) : const Color(0xFF6B46C1);
    case 'pink':
      return dark ? const Color(0xFFF29AC4) : const Color(0xFFB83280);
    case 'red':
      return dark ? const Color(0xFFF07A70) : const Color(0xFFB8322A);
    case 'orange':
      return dark ? const Color(0xFFF2A65A) : const Color(0xFFC25E10);
    case 'amber':
      return dark ? const Color(0xFFF0C55A) : const Color(0xFF9A6A00);
    case 'green':
      return dark ? const Color(0xFF74D29C) : const Color(0xFF2E7D4F);
    case 'gray':
      return dark ? const Color(0xFFA3ACB9) : const Color(0xFF6B7585);
    default: // teal
      return dark ? const Color(0xFF5FD0C6) : const Color(0xFF0D7C7C);
  }
}

Color colorOf(BuildContext c, Json? committee) =>
    committeeColor(committee?['color'] as String?, Theme.of(c).brightness);

class Tones {
  static bool _d(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
  static Color red(BuildContext c) =>
      _d(c) ? const Color(0xFFF07A70) : const Color(0xFFC0362C);
  static Color amber(BuildContext c) =>
      _d(c) ? const Color(0xFFF0B55A) : const Color(0xFFA86400);
  static Color green(BuildContext c) =>
      _d(c) ? const Color(0xFF74D29C) : const Color(0xFF2E7D4F);
  static Color blue(BuildContext c) =>
      _d(c) ? const Color(0xFF86B4EE) : const Color(0xFF2F6FB5);
}

final _d = DateFormat('EEE, d MMM yyyy');
final _dt = DateFormat('EEE, d MMM · HH:mm');
final _t = DateFormat('HH:mm');

String fmtDate(String? iso) =>
    iso == null ? '—' : _d.format(DateTime.parse(iso));
String fmtDateTime(String? iso) =>
    iso == null ? '' : _dt.format(DateTime.parse(iso).toLocal());
String fmtTime(String? iso) =>
    iso == null ? '' : _t.format(DateTime.parse(iso).toLocal());
String isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
String isoDateTime(DateTime d) => DateFormat("yyyy-MM-dd'T'HH:mm").format(d);

/// "just now", "5m", "3h", "Yesterday", "Mon", "12 Nov".
String ago(String? iso) {
  if (iso == null) return '';
  final t = DateTime.parse(iso).toLocal();
  final now = DateTime.now();
  final diff = now.difference(t);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24 && t.day == now.day) return '${diff.inHours}h';
  final days = DateUtils.dateOnly(now).difference(DateUtils.dateOnly(t)).inDays;
  if (days == 1) return 'Yesterday';
  if (days < 7) return DateFormat('EEE').format(t);
  return DateFormat(t.year == now.year ? 'd MMM' : 'd MMM yyyy').format(t);
}

/// "Today 21:00", "Tomorrow 20:30", "Thu 21:00", "12 Dec 21:00".
String whenLabel(String? iso) {
  if (iso == null) return '';
  final t = DateTime.parse(iso).toLocal();
  final days = DateUtils.dateOnly(t)
      .difference(DateUtils.dateOnly(DateTime.now()))
      .inDays;
  final time = _t.format(t);
  if (days == 0) return 'Today $time';
  if (days == 1) return 'Tomorrow $time';
  if (days == -1) return 'Yesterday $time';
  if (days > 1 && days < 7) return '${DateFormat('EEE').format(t)} $time';
  return '${DateFormat('d MMM').format(t)} $time';
}

void toast(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? Tones.red(context) : null,
      duration: Duration(milliseconds: error ? 4000 : 2200),
    ),
  );
}

/// Shows an API error; logs out if the token was revoked.
void showApiError(BuildContext context, Object e) {
  if (e is ApiException && e.unauthorized) {
    AppScope.read(context).handleSessionExpired(context);
    return;
  }
  toast(context, e.toString(), error: true);
}

Future<T?> push<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

Future<bool> confirm(
  BuildContext context, {
  required String title,
  String? message,
  String action = 'Confirm',
  bool danger = false,
}) async {
  final cs = Theme.of(context).colorScheme;
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(
                  backgroundColor: cs.error,
                  foregroundColor: cs.onError,
                )
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return r == true;
}

// ---------------------------------------------------------------- small pieces

class Dot extends StatelessWidget {
  const Dot(this.color, {super.key, this.size = 8});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.tone = 'neutral', this.icon});
  final String label;
  final String tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Color fg = cs.onSurfaceVariant;
    Color bg = cs.surfaceContainerHighest;
    Border? border;
    switch (tone) {
      case 'red':
        fg = Tones.red(context);
        bg = fg.withValues(alpha: .12);
      case 'amber':
        fg = Tones.amber(context);
        bg = fg.withValues(alpha: .14);
      case 'green':
        fg = Tones.green(context);
        bg = fg.withValues(alpha: .13);
      case 'blue':
        fg = Tones.blue(context);
        bg = fg.withValues(alpha: .13);
      case 'brand':
        fg = cs.onPrimaryContainer;
        bg = cs.primaryContainer;
      case 'ghost':
        bg = Colors.transparent;
        border = Border.all(color: cs.outlineVariant);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
        border: border,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// A committee name with its colour.
class CommitteeChip extends StatelessWidget {
  const CommitteeChip(this.c, {super.key, this.small = false});
  final Json? c;
  final bool small;
  @override
  Widget build(BuildContext context) {
    if (c == null) return const SizedBox.shrink();
    final color = colorOf(context, c);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 8 : 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (c!['is_core'] == true) ...[
            Icon(Icons.star_rounded, size: 13, color: color),
            const SizedBox(width: 3),
          ] else ...[
            Dot(color, size: 7),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              c!['name'] as String,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: small ? 11.5 : 12.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shrinks slightly while pressed — a light, responsive feel for tappable cards.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius = 14,
  });
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double borderRadius;
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _down ? .975 : 1,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          onTap: widget.onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  widget.onTap!();
                },
          onLongPress: widget.onLongPress,
          onHighlightChanged: (v) => setState(() => _down = v),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Fades and lifts a child in once, after a small delay by position.
class Appear extends StatelessWidget {
  const Appear({super.key, required this.index, required this.child});
  final int index;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final delay = index.clamp(0, 8) * 45;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + delay),
      curve: Interval(delay / (320 + delay), 1, curve: Curves.easeOutCubic),
      builder: (_, v, c) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: c),
      ),
      child: child,
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
      child: Row(
        children: [
          Text(
            text.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              letterSpacing: .8,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// A "See all" link for section titles.
class SeeAll extends StatelessWidget {
  const SeeAll({super.key, required this.onTap, this.label = 'See all'});
  final VoidCallback onTap;
  final String label;
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(8),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    ),
  );
}

/// A card that holds a list of rows separated by thin lines.
class ListCard extends StatelessWidget {
  const ListCard({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        items.add(
          Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: cs.outlineVariant.withValues(alpha: .6),
          ),
        );
      }
      items.add(children[i]);
    }
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(children: items),
    );
  }
}

class Meta extends StatelessWidget {
  const Meta(this.parts, {super.key, this.dot});
  final List<String> parts;
  final Color? dot;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = parts.where((p) => p.isNotEmpty).join('  ·  ');
    return Row(
      children: [
        if (dot != null) ...[Dot(dot!), const SizedBox(width: 7)],
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// Small red count bubble.
class CountBadge extends StatelessWidget {
  const CountBadge(this.count, {super.key, required this.child});
  final int count;
  final Widget child;
  @override
  Widget build(BuildContext context) => Badge(
    isLabelVisible: count > 0,
    label: Text(count > 99 ? '99+' : '$count'),
    child: child,
  );
}

/// Several initials avatars overlapping, e.g. task assignees.
class AvatarStack extends StatelessWidget {
  const AvatarStack(this.people, {super.key, this.max = 3, this.radius = 12});
  final List<Json> people;
  final int max;
  final double radius;
  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final shown = people.take(max).toList();
    final extra = people.length - shown.length;
    final step = radius * 1.35;
    final count = shown.length + (extra > 0 ? 1 : 0);
    return SizedBox(
      width: step * (count - 1) + radius * 2,
      height: radius * 2,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: step * i,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Theme.of(context).cardColor, width: 1.5),
                ),
                child: Initials(shown[i]['name'] as String, radius: radius - 1.5),
              ),
            ),
          if (extra > 0)
            Positioned(
              left: step * shown.length,
              child: CircleAvatar(
                radius: radius,
                backgroundColor: cs.surfaceContainerHighest,
                child: Text(
                  '+$extra',
                  style: TextStyle(
                    fontSize: radius * .7,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- tiles

String priorityTone(int p) => p >= 4
    ? 'red'
    : p == 3
    ? 'amber'
    : 'neutral';

class TaskTile extends StatelessWidget {
  const TaskTile(this.t, {super.key, required this.onTap, this.hideCommittee = false});
  final Json t;
  final VoidCallback onTap;
  final bool hideCommittee;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pill = t['pill'] as Json?;
    final pri = t['priority'] as int;
    final closed = t['is_closed'] == true;
    final edge = closed
        ? null
        : pri >= 4
        ? Tones.red(context)
        : pri == 3
        ? Tones.amber(context)
        : null;
    final assignees = (t['assignees'] as List).cast<Json>();
    final status = t['status'] as String;
    return Pressable(
      onTap: onTap,
      borderRadius: 0,
      child: Container(
        decoration: BoxDecoration(
          border: edge == null ? null : Border(left: BorderSide(color: edge, width: 3)),
        ),
        padding: EdgeInsets.fromLTRB(edge == null ? 16 : 13, 12, 14, 12),
        child: Row(
          children: [
            _StatusRing(status: status),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t['title'] as String,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15.5,
                      color: closed ? cs.onSurfaceVariant : null,
                      decoration: status == 'cancelled' ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      if (pill != null) ...[
                        Pill(pill['label'] as String, tone: pill['tone'] as String),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Meta(
                          [
                            if (!hideCommittee) (t['committee'] as Json)['name'] as String,
                            if (!closed) t['status_label'] as String,
                          ],
                          dot: hideCommittee ? null : colorOf(context, t['committee'] as Json),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (assignees.isNotEmpty) ...[
              const SizedBox(width: 8),
              AvatarStack(assignees),
            ],
          ],
        ),
      ),
    );
  }
}

/// A small ring that fills in as a task moves along.
class _StatusRing extends StatelessWidget {
  const _StatusRing({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (value, color, icon) = switch (status) {
      'doing' => (.5, cs.primary, null),
      'waiting' => (.75, Tones.amber(context), null),
      'done' => (1.0, Tones.green(context), Icons.check_rounded),
      'cancelled' => (1.0, cs.outline, Icons.close_rounded),
      _ => (0.0, cs.outline, null),
    };
    return SizedBox(
      width: 24,
      height: 24,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => CircularProgressIndicator(
              value: v,
              strokeWidth: 2.6,
              backgroundColor: cs.outlineVariant,
              color: color,
              strokeCap: StrokeCap.round,
            ),
          ),
          if (icon != null) Icon(icon, size: 14, color: color),
        ],
      ),
    );
  }
}

class AnnouncementCard extends StatelessWidget {
  const AnnouncementCard(this.a, {super.key, required this.onTap, this.compact = false});
  final Json a;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final unread = a['read'] != true;
    final needAck = a['requires_ack'] == true && a['is_recipient'] == true && a['acked'] != true;
    final from = a['posted_as'] as Json?;
    final author = a['author'] as Json?;
    final urgent = a['urgent'] == true;
    final accent = urgent ? Tones.red(context) : colorOf(context, from);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Pressable(
        onTap: onTap,
        borderRadius: 16,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: unread ? 4 : 0,
                color: accent,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (author != null) ...[
                            Initials(author['name'] as String, radius: 13),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              [
                                author?['name'] as String? ?? '',
                                if (from != null) from['name'] as String,
                              ].where((s) => s.isNotEmpty).join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
                            ),
                          ),
                          Text(
                            ago(a['created_at'] as String?),
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                          ),
                          if (unread) ...[
                            const SizedBox(width: 6),
                            Dot(accent, size: 8),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (a['pinned'] == true) ...[
                            Icon(Icons.push_pin_rounded, size: 16, color: cs.primary),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              a['title'] as String,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: unread ? FontWeight.w800 : FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (!compact) ...[
                        const SizedBox(height: 4),
                        Text(
                          a['body'] as String,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: cs.onSurfaceVariant, height: 1.35),
                        ),
                      ],
                      if (urgent || needAck || a['audience'] != 'all') ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (urgent) const Pill('Urgent', tone: 'red', icon: Icons.priority_high_rounded),
                            if (needAck)
                              const Pill('Please acknowledge', tone: 'amber', icon: Icons.touch_app_outlined),
                            if (a['audience'] != 'all')
                              Pill(a['audience_label'] as String, tone: 'ghost', icon: Icons.group_outlined),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String rsvpLabel(String? r) => switch (r) {
  'going' => 'Going',
  'maybe' => 'Maybe',
  'declined' => "Can't come",
  'pending' => 'Reply needed',
  _ => '',
};

String rsvpTone(String? r) => switch (r) {
  'going' => 'green',
  'maybe' => 'amber',
  'declined' => 'red',
  'pending' => 'blue',
  _ => 'neutral',
};

class MeetingTile extends StatelessWidget {
  const MeetingTile(this.m, {super.key, required this.onTap});
  final Json m;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final start = DateTime.parse(m['start'] as String).toLocal();
    final off = m['cancelled'] == true;
    final c = m['committee'] as Json?;
    final color = c == null ? cs.primary : colorOf(context, c);
    final rsvp = m['my_rsvp'] as String?;
    final counts = m['counts'] as Json;
    return Pressable(
      onTap: onTap,
      borderRadius: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 54,
              decoration: BoxDecoration(
                color: color.withValues(alpha: off ? .06 : .13),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat('MMM').format(start).toUpperCase(),
                    style: TextStyle(fontSize: 10.5, letterSpacing: .6, fontWeight: FontWeight.w800, color: color),
                  ),
                  Text(
                    '${start.day}',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.1, color: off ? cs.onSurfaceVariant : null),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m['title'] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15.5,
                      decoration: off ? TextDecoration.lineThrough : null,
                      color: off ? cs.onSurfaceVariant : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Meta([
                    DateFormat('EEE HH:mm').format(start),
                    m['scope_label'] as String,
                    (m['location'] as String?) ?? '',
                  ]),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (off)
                        const Pill('Cancelled', tone: 'red')
                      else if (rsvp != null && m['is_past'] != true)
                        Pill(rsvpLabel(rsvp), tone: rsvpTone(rsvp)),
                      if (m['has_minutes'] == true) ...[
                        const SizedBox(width: 6),
                        const Pill('Minutes', tone: 'ghost', icon: Icons.description_outlined),
                      ],
                      const Spacer(),
                      Icon(Icons.check_circle_outline, size: 15, color: Tones.green(context)),
                      const SizedBox(width: 3),
                      Text('${counts['going']}', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                    ],
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

class PersonTile extends StatelessWidget {
  const PersonTile(this.p, {super.key, this.onTap, this.subtitle, this.trailing});
  final Json p;
  final VoidCallback? onTap;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = subtitle ?? (p['title'] as String? ?? '');
    return Pressable(
      onTap: onTap,
      borderRadius: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: Row(
          children: [
            Initials(p['name'] as String, radius: 19),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  if (sub.isNotEmpty)
                    Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- states

class EmptyView extends StatelessWidget {
  const EmptyView(this.text, {super.key, this.icon = Icons.inbox_outlined, this.action});
  final String text;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: cs.primaryContainer.withValues(alpha: .5), shape: BoxShape.circle),
            child: Icon(icon, size: 34, color: cs.primary),
          ),
          const SizedBox(height: 14),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
          if (action != null) ...[const SizedBox(height: 14), action!],
        ],
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView(this.error, {super.key, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => EmptyView(
    error.toString(),
    icon: Icons.cloud_off_outlined,
    action: FilledButton.tonal(onPressed: onRetry, child: const Text('Try again')),
  );
}

/// Placeholder rows that shimmer while the first load is running.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.rows = 5});
  final int rows;
  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget bar(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: .08), borderRadius: BorderRadius.circular(8)),
    );
    return FadeTransition(
      opacity: Tween(begin: .45, end: 1.0).animate(_c),
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          for (var i = 0; i < widget.rows; i++)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(width: 36, height: 36, decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: .08), shape: BoxShape.circle)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [bar(180 - i * 14.0, 13), const SizedBox(height: 8), bar(110, 10)],
                      ),
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

/// Loads JSON, shows a skeleton / error / content, reloads on pull-down and when data changes elsewhere.
class Loader extends StatefulWidget {
  const Loader({super.key, required this.load, required this.builder, this.skeletonRows = 5});
  final Future<Json> Function() load;
  final Widget Function(BuildContext, Json, Future<void> Function() reload) builder;
  final int skeletonRows;
  @override
  State<Loader> createState() => _LoaderState();
}

class _LoaderState extends State<Loader> {
  Json? _data;
  Object? _error;
  int _seen = -1;

  Future<void> _reload() async {
    try {
      final d = await widget.load();
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.unauthorized) {
        AppScope.read(context).handleSessionExpired(context);
        return;
      }
      if (_data != null) {
        toast(context, e.toString(), error: true);
      } else {
        setState(() => _error = e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = AppScope.of(context).dataVersion;
    if (v != _seen) {
      _seen = v;
      Future.microtask(_reload);
    }
    Widget child;
    if (_data != null) {
      child = KeyedSubtree(key: const ValueKey('data'), child: widget.builder(context, _data!, _reload));
    } else if (_error != null) {
      child = ListView(
        children: [
          ErrorView(_error!, onRetry: () {
            setState(() => _error = null);
            _reload();
          }),
        ],
      );
    } else {
      child = Skeleton(key: const ValueKey('loading'), rows: widget.skeletonRows);
    }
    return AnimatedSwitcher(duration: const Duration(milliseconds: 260), child: child);
  }
}

/// Standard scrollable page body with pull-to-refresh.
class RefreshList extends StatelessWidget {
  const RefreshList({super.key, required this.onRefresh, required this.children, this.padding, this.controller});
  final Future<void> Function() onRefresh;
  final List<Widget> children;
  final EdgeInsets? padding;
  final ScrollController? controller;
  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        HapticFeedback.lightImpact();
        await onRefresh();
      },
      child: ListView(
        controller: controller,
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: padding ?? const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: children,
      ),
    );
  }
}

/// Segmented tabs with a sliding highlight (e.g. Upcoming / Past).
class Segments<T> extends StatelessWidget {
  const Segments({super.key, required this.items, required this.value, required this.onChanged});
  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final index = items.indexWhere((i) => i.$1 == value);
    return Container(
      height: 42,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .7), borderRadius: BorderRadius.circular(14)),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth / items.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                left: w * index,
                top: 0,
                bottom: 0,
                width: w,
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .08), blurRadius: 6, offset: const Offset(0, 1))],
                  ),
                ),
              ),
              Row(
                children: [
                  for (final i in items)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (i.$1 == value) return;
                          HapticFeedback.selectionClick();
                          onChanged(i.$1);
                        },
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: i.$1 == value ? cs.onSurface : cs.onSurfaceVariant,
                            ),
                            child: Text(i.$2, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Horizontally scrolling filter chips.
class ChipRow extends StatelessWidget {
  const ChipRow({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          for (final c in children) Padding(padding: const EdgeInsets.only(right: 8), child: c),
        ],
      ),
    ),
  );
}

/// Committee filter chips: All + each committee (optionally only mine).
class CommitteeFilter extends StatelessWidget {
  const CommitteeFilter({super.key, required this.value, required this.onChanged, this.ids});
  final int? value;
  final ValueChanged<int?> onChanged;
  final Set<int>? ids;
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final list = app.committees.where((c) => ids == null || ids!.contains(c['id'])).toList();
    if (list.length < 2) return const SizedBox.shrink();
    Widget chip(String label, int? id, {Color? color}) => ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (color != null) ...[Dot(color), const SizedBox(width: 6)],
          Text(label),
        ],
      ),
      selected: value == id,
      showCheckmark: false,
      onSelected: (_) {
        HapticFeedback.selectionClick();
        onChanged(id);
      },
    );
    return ChipRow(
      children: [
        chip('All', null),
        for (final c in list) chip(c['name'] as String, c['id'] as int, color: colorOf(context, c)),
      ],
    );
  }
}

// ---------------------------------------------------------------- contacts

class ContactActions extends StatelessWidget {
  const ContactActions({super.key, this.phone, this.email});
  final String? phone;
  final String? email;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    if ((phone ?? '').isNotEmpty) {
      final digits = phone!.replaceAll(RegExp(r'[^0-9+]'), '');
      rows.add(_row(context, Icons.call_outlined, phone!, 'tel:$digits',
          extra: IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'WhatsApp',
            icon: Icon(Icons.chat_outlined, size: 18, color: Tones.green(context)),
            onPressed: () => launchUrl(Uri.parse('https://wa.me/${digits.replaceAll('+', '')}'),
                mode: LaunchMode.externalApplication),
          )));
    }
    if ((email ?? '').isNotEmpty) {
      rows.add(_row(context, Icons.mail_outline, email!, 'mailto:$email'));
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  Widget _row(BuildContext context, IconData icon, String value, String url, {Widget? extra}) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => launchUrl(Uri.parse(url)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Flexible(child: Text(value, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w500))),
                ],
              ),
            ),
          ),
        ),
        ?extra,
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Copy',
          icon: Icon(Icons.copy_rounded, size: 18, color: cs.onSurfaceVariant),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: value));
            HapticFeedback.lightImpact();
            toast(context, 'Copied $value');
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- form fields

class DateField extends StatelessWidget {
  const DateField({super.key, required this.label, required this.value, required this.onChanged, this.withTime = false, this.allowClear = true});
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool withTime;
  final bool allowClear;

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? ''
        : (withTime ? DateFormat('EEE, d MMM yyyy · HH:mm') : DateFormat('EEE, d MMM yyyy')).format(value!);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        FocusScope.of(context).unfocus();
        final r = await showDateSheet(context, title: label.replaceAll(' (optional)', ''), initial: value,
            withTime: withTime, allowClear: allowClear);
        if (r != null) onChanged(r.value);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: value == null || !allowClear
              ? Icon(withTime ? Icons.schedule_rounded : Icons.event_outlined)
              : IconButton(icon: const Icon(Icons.close), onPressed: () => onChanged(null)),
        ),
        isEmpty: value == null,
        child: Text(text),
      ),
    );
  }
}

/// Field showing chosen people; opens a searchable multi-select sheet.
class PeopleField extends StatelessWidget {
  const PeopleField({super.key, required this.label, required this.people, required this.value, required this.onChanged, this.placeholder = 'Nobody yet'});
  final String label;
  final List<Json> people;
  final Set<int> value;
  final ValueChanged<Set<int>> onChanged;
  final String placeholder;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chosen = people.where((p) => value.contains(p['id'])).toList();
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        FocusScope.of(context).unfocus();
        final r = await showMultiPicker<int>(
          context,
          title: label,
          selected: value,
          searchable: people.length > 8,
          groups: [
            PickGroup([
              for (final p in people)
                PickOption(p['id'] as int, p['name'] as String,
                    subtitle: (p['title'] as String?)?.isNotEmpty == true ? p['title'] as String : null,
                    leading: Initials(p['name'] as String)),
            ]),
          ],
        );
        if (r != null) onChanged(r);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.person_add_alt_1_outlined)),
        child: chosen.isEmpty
            ? Text(placeholder, style: TextStyle(color: cs.onSurfaceVariant))
            : Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in chosen)
                    Container(
                      padding: const EdgeInsets.fromLTRB(3, 3, 10, 3),
                      decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(99)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Initials(p['name'] as String, radius: 11),
                          const SizedBox(width: 6),
                          Text(p['name'] as String, style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSecondaryContainer)),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// Single committee picker.
class CommitteeField extends StatelessWidget {
  const CommitteeField({super.key, required this.committees, required this.value, required this.onChanged, this.label = 'Committee', this.noneLabel});
  final List<Json> committees;
  final int? value;
  final ValueChanged<int?> onChanged;
  final String label;
  final String? noneLabel;
  @override
  Widget build(BuildContext context) {
    return PickerField<int?>(
      label: label,
      value: value,
      placeholder: noneLabel ?? 'Choose…',
      onChanged: onChanged,
      groups: [
        PickGroup([
          if (noneLabel != null) PickOption<int?>(null, noneLabel!, icon: Icons.public_rounded),
          for (final c in committees)
            PickOption<int?>(c['id'] as int, c['name'] as String, color: colorOf(context, c),
                subtitle: c['is_core'] == true ? 'Core committee' : null),
        ]),
      ],
    );
  }
}

/// Shows field errors from the API under the right inputs.
String? fieldError(ApiException? e, String field) {
  final list = e?.fieldErrors[field];
  return (list == null || list.isEmpty) ? null : list.first;
}

/// Bottom sheet with a title, used for quick actions and small forms.
Future<T?> showSheet<T>(BuildContext context, {required String title, required Widget Function(BuildContext) builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            builder(ctx),
          ],
        ),
      ),
    ),
  );
}

/// A filled button that shows a spinner while [onPressed] runs.
class BusyButton extends StatefulWidget {
  const BusyButton({super.key, required this.label, required this.onPressed, this.icon, this.tonal = false});
  final String label;
  final Future<void> Function()? onPressed;
  final IconData? icon;
  final bool tonal;
  @override
  State<BusyButton> createState() => _BusyButtonState();
}

class _BusyButtonState extends State<BusyButton> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final child = AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: _busy
          ? const SizedBox(key: ValueKey('b'), width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
          : Row(
              key: const ValueKey('l'),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[Icon(widget.icon, size: 19), const SizedBox(width: 8)],
                Text(widget.label),
              ],
            ),
    );
    final onPressed = widget.onPressed == null || _busy
        ? null
        : () async {
            HapticFeedback.mediumImpact();
            setState(() => _busy = true);
            try {
              await widget.onPressed!();
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          };
    return widget.tonal
        ? FilledButton.tonal(onPressed: onPressed, child: child)
        : FilledButton(onPressed: onPressed, child: child);
  }
}

/// Labelled block of text on detail pages.
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.icon, required this.label, required this.child, this.onTap});
  final IconData icon;
  final String label;
  final Widget child;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: cs.primaryContainer.withValues(alpha: .55), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 18, color: cs.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  DefaultTextStyle.merge(style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500), child: child),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- brand

/// The unit's mark: a rounded tile with people.
/// The association's logo: the full seal when large, the emblem (no small text) when small.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 64});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      boxShadow: [BoxShadow(color: brand.withValues(alpha: .30), blurRadius: size * .3, offset: Offset(0, size * .08))],
    ),
    child: Image.asset(
      size >= 72 ? 'assets/seal.png' : 'assets/emblem.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
    ),
  );
}
