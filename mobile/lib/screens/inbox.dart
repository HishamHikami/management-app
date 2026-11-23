import 'package:material_ui/material_ui.dart';

import '../api.dart';
import '../state.dart';
import '../ui.dart';
import 'announcements.dart';
import 'meetings.dart';
import 'tasks.dart';

/// Everything that happened for you: new tasks, updates, announcements, meetings.
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inbox'),
        actions: [
          if (app.count('notifications') > 0)
            TextButton(
              onPressed: () async {
                try {
                  final r = await app.api!.post('notifications/read');
                  app.setCounts(r['counts']);
                  app.changed();
                } catch (e) {
                  if (context.mounted) showApiError(context, e);
                }
              },
              child: const Text('Mark all read'),
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: Loader(
        load: () => app.api!.get('notifications'),
        builder: (context, d, reload) {
          final items = (d['notifications'] as List).cast<Json>();
          if (items.isEmpty) {
            return RefreshList(
              onRefresh: reload,
              children: const [EmptyView('Nothing here yet. New tasks, announcements and meetings will show up here.', icon: Icons.notifications_none_rounded)],
            );
          }
          return RefreshList(
            onRefresh: reload,
            children: [
              ListCard(
                children: [
                  for (var i = 0; i < items.length; i++) Appear(index: i, child: _Row(n: items[i])),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.n});
  final Json n;
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final unread = n['read'] != true;
    final (icon, color) = switch (n['kind']) {
      'task' => (Icons.task_alt_rounded, cs.primary),
      'announcement' => (Icons.campaign_rounded, Tones.amber(context)),
      'meeting' => (Icons.event_rounded, Tones.blue(context)),
      _ => (Icons.notifications_rounded, cs.outline),
    };
    return Pressable(
      borderRadius: 0,
      onTap: () async {
        final id = n['object_id'] as int?;
        if (unread) {
          app.api!.post('notifications/read', {'ids': [n['id']]}).then((r) => app.setCounts(r['counts'])).catchError((_) {});
        }
        if (id == null) return;
        final page = switch (n['kind']) {
          'task' => TaskDetailScreen(id: id) as Widget,
          'announcement' => AnnouncementDetailScreen(id: id),
          'meeting' => MeetingDetailScreen(id: id),
          _ => null,
        };
        if (page != null) await push(context, page);
        app.changed();
      },
      child: Container(
        color: unread ? cs.primaryContainer.withValues(alpha: .18) : null,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: color.withValues(alpha: .14), shape: BoxShape.circle),
              child: Icon(icon, size: 19, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(n['title'] as String, style: TextStyle(fontWeight: unread ? FontWeight.w700 : FontWeight.w500, fontSize: 15)),
                  if ((n['body'] as String).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(n['body'] as String, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13.5, color: cs.onSurfaceVariant)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(ago(n['at'] as String?), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                if (unread) ...[const SizedBox(height: 6), Dot(cs.primary)],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
