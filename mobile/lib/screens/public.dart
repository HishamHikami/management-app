import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../state.dart';
import '../ui.dart';
import 'login.dart';
import 'profile.dart';

/// The app as anyone sees it: no account needed. Members reach their area from "Me".
class PublicShell extends StatefulWidget {
  const PublicShell({super.key});
  @override
  State<PublicShell> createState() => _PublicShellState();
}

class _PublicShellState extends State<PublicShell> {
  int _index = 0;
  final _keys = List.generate(5, (_) => GlobalKey<NavigatorState>());

  Widget _root(int i) => switch (i) {
    0 => const PublicHomeScreen(),
    1 => const VideosScreen(),
    2 => const ProgramsScreen(),
    3 => const WhosWhoScreen(),
    _ => const PublicMeScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (app.openTarget != null && app.openTarget!.kind == 'public') {
      final t = app.takeOpenTarget()!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() => _index = 0);
        _keys[0].currentState?.push(MaterialPageRoute(builder: (_) => PostDetailScreen(id: t.id)));
      });
    }
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
        body: IndexedStack(
          index: _index,
          children: [
            for (var i = 0; i < 5; i++)
              Navigator(key: _keys[i], onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => _root(i))),
          ],
        ),
        bottomNavigationBar: MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.1)),
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) {
              HapticFeedback.selectionClick();
              if (i == _index) {
                _keys[i].currentState?.popUntil((r) => r.isFirst);
              } else {
                setState(() => _index = i);
              }
            },
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: [
              const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
              const NavigationDestination(icon: Icon(Icons.play_circle_outline_rounded), selectedIcon: Icon(Icons.play_circle_rounded), label: 'Videos'),
              const NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book_rounded), label: 'QHLS'),
              const NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups_rounded), label: "Who's who"),
              NavigationDestination(
                icon: app.api == null ? const Icon(Icons.person_outline_rounded) : Initials((app.me['name'] as String?) ?? '?', radius: 12),
                label: 'Me',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ======================================================================= helpers

String? youtubeId(String url) {
  final m = RegExp(r'(?:youtu\.be/|v=|/embed/|/live/|/shorts/)([A-Za-z0-9_-]{11})').firstMatch(url);
  return m?.group(1);
}

Future<void> openLink(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

String _when(String? iso) => iso == null ? '' : DateFormat('EEE d MMM · HH:mm').format(DateTime.parse(iso).toLocal());

/// A 16:9 YouTube thumbnail (or a gradient when the link isn't YouTube).
class VideoThumb extends StatelessWidget {
  const VideoThumb({super.key, required this.url, this.live = false});
  final String url;
  final bool live;
  @override
  Widget build(BuildContext context) {
    final id = youtubeId(url);
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (id != null)
            Image.network('https://img.youtube.com/vi/$id/hqdefault.jpg', fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const _ThumbFallback())
          else
            const _ThumbFallback(),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withValues(alpha: .35)]),
            ),
          ),
          const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 52)),
          if (live)
            const Positioned(left: 10, top: 10, child: LiveBadge()),
        ],
      ),
    );
  }
}

class _ThumbFallback extends StatelessWidget {
  const _ThumbFallback();
  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(gradient: LinearGradient(colors: brandGradient)),
    child: const Center(child: Icon(Icons.ondemand_video_rounded, color: gold, size: 40)),
  );
}

class LiveBadge extends StatefulWidget {
  const LiveBadge({super.key});
  @override
  State<LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<LiveBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: const Color(0xFFE53935), borderRadius: BorderRadius.circular(6)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeTransition(opacity: _c, child: const Dot(Colors.white, size: 7)),
        const SizedBox(width: 5),
        const Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11.5, letterSpacing: .8)),
      ],
    ),
  );
}

List<Widget> _publicActions(BuildContext context) {
  final app = AppScope.of(context);
  return [
    if (app.api != null)
      IconButton(
        tooltip: 'Inbox',
        icon: CountBadge(app.count('notifications'), child: const Icon(Icons.notifications_none_rounded)),
        onPressed: () => push(context, const _PublicInbox()),
      ),
    const SizedBox(width: 4),
  ];
}

// ======================================================================= home

class PublicHomeScreen extends StatelessWidget {
  const PublicHomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(children: [const BrandMark(size: 30), const SizedBox(width: 10), Flexible(child: Text(app.shortName, overflow: TextOverflow.ellipsis))]),
        actions: _publicActions(context),
      ),
      floatingActionButton: app.can('public')
          ? FloatingActionButton.extended(
              heroTag: 'pub-fab',
              onPressed: () => push(context, const PostEditor()),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Post'),
            )
          : null,
      body: Loader(
        load: () => app.client.get('public/home'),
        builder: (context, d, reload) {
          final live = (d['live'] as List).cast<Json>();
          final events = (d['events'] as List).cast<Json>();
          final news = (d['news'] as List).cast<Json>();
          final videos = (d['videos'] as List).cast<Json>();
          final programs = (d['programs'] as List).cast<Json>();
          final cs = Theme.of(context).colorScheme;
          var i = 0;
          return RefreshList(
            onRefresh: reload,
            children: [
              Appear(
                index: i++,
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: brandGradient),
                  ),
                  child: Row(
                    children: [
                      const BrandMark(size: 64),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(app.orgName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16.5, height: 1.25)),
                            const SizedBox(height: 4),
                            const Text('Events, classes, live sessions and more', style: TextStyle(color: Colors.white70, fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              for (final x in live) ...[
                const SizedBox(height: 14),
                Appear(index: i++, child: _LiveCard(x: x)),
              ],
              if (programs.isNotEmpty) ...[
                const SectionTitle('Programmes'),
                for (final pr in programs) Appear(index: i++, child: _ProgramCard(pr: pr)),
              ],
              if (events.isNotEmpty) ...[
                const SectionTitle('Coming up'),
                Appear(index: i++, child: ListCard(children: [for (final e in events) _EventTile(e: e)])),
              ],
              if (news.isNotEmpty) ...[
                const SectionTitle('News'),
                for (final n in news) Appear(index: i++, child: _NewsCard(x: n)),
              ],
              if (videos.isNotEmpty) ...[
                const SectionTitle('Recent videos'),
                SizedBox(
                  height: 178,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final v in videos)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: SizedBox(width: 240, child: _VideoCard(v: v, compact: true)),
                        ),
                    ],
                  ),
                ),
              ],
              if (live.isEmpty && events.isEmpty && news.isEmpty && videos.isEmpty && programs.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: EmptyView('News, events and videos will appear here.', icon: Icons.campaign_outlined,
                      action: app.can('public') ? FilledButton.tonal(onPressed: () => push(context, const PostEditor()), child: const Text('Post something')) : null),
                ),
              if (app.api == null) ...[
                const SizedBox(height: 22),
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: Icon(Icons.how_to_reg_outlined, color: cs.primary),
                    title: const Text('Stay connected'),
                    subtitle: const Text('Register to get announcements and updates'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => push(context, const RegisterScreen()),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.x});
  final Json x;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: Pressable(
      borderRadius: 18,
      onTap: () => openLink(x['link'] as String),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VideoThumb(url: x['link'] as String, live: true),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Row(
              children: [
                Expanded(child: Text(x['title'] as String, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                FilledButton.icon(onPressed: () => openLink(x['link'] as String), icon: const Icon(Icons.play_arrow_rounded), label: const Text('Watch')),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _ProgramCard extends StatelessWidget {
  const _ProgramCard({required this.pr});
  final Json pr;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reg = (pr['registration_url'] as String?) ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Pressable(
        borderRadius: 18,
        onTap: () => push(context, ProgramDetailScreen(id: pr['id'] as int)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: gold.withValues(alpha: .22), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.menu_book_rounded, color: Color(0xFF8A6100)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pr['name'] as String, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                    if ((pr['schedule'] as String).isNotEmpty)
                      Text(pr['schedule'] as String, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              if (reg.isNotEmpty)
                FilledButton.tonal(onPressed: () => openLink(reg), child: const Text('Register'))
              else
                Icon(Icons.chevron_right_rounded, color: cs.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.e});
  final Json e;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final start = DateTime.parse(e['starts_at'] as String).toLocal();
    return Pressable(
      borderRadius: 0,
      onTap: () => push(context, PostDetailScreen(id: e['id'] as int)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 54,
              decoration: BoxDecoration(color: cs.primaryContainer.withValues(alpha: .6), borderRadius: BorderRadius.circular(14)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(DateFormat('MMM').format(start).toUpperCase(), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: cs.primary)),
                  Text('${start.day}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.1)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e['title'] as String, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 3),
                  Meta([DateFormat('EEE HH:mm').format(start), (e['location'] as String?) ?? '']),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.x});
  final Json x;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Pressable(
        borderRadius: 18,
        onTap: () => push(context, PostDetailScreen(id: x['id'] as int)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (x['pinned'] == true) ...[Icon(Icons.push_pin_rounded, size: 16, color: cs.primary), const SizedBox(width: 4)],
                  Expanded(child: Text(x['title'] as String, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5))),
                  Text(ago(x['created_at'] as String?), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
              if ((x['body'] as String).isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(x['body'] as String, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, height: 1.35)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.v, this.compact = false});
  final Json v;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: compact ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Pressable(
        borderRadius: 18,
        onTap: () => openLink(v['link'] as String),
        onLongPress: AppScope.read(context).can('public') ? () => push(context, PostEditor(existing: v)) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VideoThumb(url: v['link'] as String, live: v['is_live'] == true),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(v['title'] as String, maxLines: compact ? 1 : 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (!compact && (v['body'] as String).isNotEmpty)
                    Text(v['body'] as String, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================= post detail

class PostDetailScreen extends StatelessWidget {
  const PostDetailScreen({super.key, required this.id});
  final int id;
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Loader(
      load: () => app.client.get('public/posts/$id'),
      builder: (context, d, reload) {
        final x = d['post'] as Json;
        final cs = Theme.of(context).colorScheme;
        final link = (x['link'] as String?) ?? '';
        return Scaffold(
          appBar: AppBar(actions: [
            if (app.can('public'))
              IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () async {
                await push(context, PostEditor(existing: x));
                reload();
              }),
          ]),
          body: RefreshList(
            onRefresh: reload,
            children: [
              if (link.isNotEmpty && youtubeId(link) != null) ...[
                ClipRRect(borderRadius: BorderRadius.circular(18), child: GestureDetector(onTap: () => openLink(link), child: VideoThumb(url: link, live: x['is_live'] == true))),
                const SizedBox(height: 14),
              ],
              Wrap(spacing: 6, children: [
                Pill(x['kind_label'] as String, tone: 'brand'),
                if (x['is_live'] == true) const LiveBadge(),
              ]),
              const SizedBox(height: 10),
              Text(x['title'] as String, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              if (x['starts_at'] != null)
                InfoRow(icon: Icons.schedule_rounded, label: 'WHEN', child: Text(_when(x['starts_at'] as String?) + (x['ends_at'] != null ? ' – ${fmtTime(x['ends_at'] as String?)}' : ''))),
              if ((x['location'] as String).isNotEmpty)
                InfoRow(icon: Icons.place_outlined, label: 'WHERE', child: Text(x['location'] as String),
                    onTap: () => openLink('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(x['location'] as String)}')),
              if ((x['body'] as String).isNotEmpty) ...[
                const SizedBox(height: 8),
                SelectableText(x['body'] as String, style: TextStyle(fontSize: 16, height: 1.55, color: cs.onSurface)),
              ],
              if (link.isNotEmpty) ...[
                const SizedBox(height: 20),
                FilledButton.icon(onPressed: () => openLink(link), icon: Icon(x['kind'] == 'event' ? Icons.open_in_new_rounded : Icons.play_arrow_rounded),
                    label: Text(x['kind'] == 'event' ? 'Open link' : 'Watch')),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ======================================================================= videos

class VideosScreen extends StatefulWidget {
  const VideosScreen({super.key});
  @override
  State<VideosScreen> createState() => _VideosScreenState();
}

class _VideosScreenState extends State<VideosScreen> {
  String _cat = '';
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    const cats = [('', 'All'), ('qhls', 'QHLS'), ('event', 'Events'), ('lecture', 'Lectures'), ('other', 'Other')];
    return Scaffold(
      appBar: AppBar(title: const Text('Videos'), actions: _publicActions(context)),
      floatingActionButton: app.can('public')
          ? FloatingActionButton(heroTag: 'vid-fab', onPressed: () => push(context, const PostEditor(kind: 'video')), child: const Icon(Icons.add_rounded))
          : null,
      body: Column(
        children: [
          ChipRow(children: [
            for (final c in cats)
              ChoiceChip(label: Text(c.$2), selected: _cat == c.$1, showCheckmark: false, onSelected: (_) => setState(() => _cat = c.$1)),
          ]),
          Expanded(
            child: Loader(
              key: ValueKey('v-$_cat'),
              load: () => app.client.get('public/posts', query: {'kind': 'video', 'category': _cat}),
              builder: (context, d, reload) {
                final items = (d['posts'] as List).cast<Json>();
                return RefreshList(
                  onRefresh: reload,
                  children: [
                    if (items.isEmpty) const EmptyView('No videos yet.', icon: Icons.ondemand_video_outlined),
                    for (var i = 0; i < items.length; i++) Appear(index: i, child: _VideoCard(v: items[i])),
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

// ======================================================================= programmes (QHLS)

class ProgramsScreen extends StatelessWidget {
  const ProgramsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Loader(
      load: () => app.client.get('public/programs'),
      builder: (context, d, reload) {
        final items = (d['programs'] as List).cast<Json>();
        // With one programme (QHLS), show it directly.
        if (items.length == 1 && !app.can('public')) return ProgramDetailScreen(id: items.first['id'] as int, root: true);
        return Scaffold(
          appBar: AppBar(title: const Text('Programmes'), actions: _publicActions(context)),
          floatingActionButton: app.can('public')
              ? FloatingActionButton(heroTag: 'prog-fab', onPressed: () => push(context, const ProgramEditor()), child: const Icon(Icons.add_rounded))
              : null,
          body: RefreshList(
            onRefresh: reload,
            children: [
              if (items.isEmpty) const EmptyView('Programmes like QHLS will appear here.', icon: Icons.menu_book_outlined),
              for (final pr in items) _ProgramCard(pr: pr),
            ],
          ),
        );
      },
    );
  }
}

class ProgramDetailScreen extends StatelessWidget {
  const ProgramDetailScreen({super.key, required this.id, this.root = false});
  final int id;
  final bool root;
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Loader(
      load: () => app.client.get('public/programs/$id'),
      builder: (context, d, reload) {
        final pr = d['program'] as Json;
        final res = (pr['resources'] as List).cast<Json>();
        final videos = (pr['videos'] as List).cast<Json>();
        final upcoming = (pr['upcoming'] as List).cast<Json>();
        final reg = (pr['registration_url'] as String?) ?? '';
        final canEdit = app.can('public');
        final cs = Theme.of(context).colorScheme;
        Future<void> addResource() async {
          final t = TextEditingController();
          final u = TextEditingController();
          final ok = await showSheet<bool>(context, title: 'Add resource', builder: (ctx) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(controller: t, decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. Week 3 notes')),
              const SizedBox(height: 12),
              TextField(controller: u, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Link', hintText: 'Google Drive, PDF, YouTube…')),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
            ],
          ));
          if (ok != true) return;
          try {
            await app.client.post('public/programs/$id/resources', {'title': t.text, 'url': u.text});
            reload();
          } catch (e) {
            if (context.mounted) showApiError(context, e);
          }
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(((pr['short_name'] as String?) ?? '').isEmpty ? pr['name'] as String : pr['short_name'] as String),
            actions: [
              if (canEdit)
                IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () async {
                  await push(context, ProgramEditor(existing: pr));
                  reload();
                }),
              if (root) ..._publicActions(context),
            ],
          ),
          body: RefreshList(
            onRefresh: reload,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), gradient: const LinearGradient(colors: brandGradient)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pr['name'] as String, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                    if ((pr['schedule'] as String).isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(children: [const Icon(Icons.event_repeat_rounded, color: gold, size: 18), const SizedBox(width: 6),
                        Expanded(child: Text(pr['schedule'] as String, style: const TextStyle(color: Colors.white)))]),
                    ],
                    if ((pr['location'] as String).isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(children: [const Icon(Icons.place_outlined, color: gold, size: 18), const SizedBox(width: 6),
                        Expanded(child: Text(pr['location'] as String, style: const TextStyle(color: Colors.white70)))]),
                    ],
                    if (reg.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: brand),
                        onPressed: () => openLink(reg),
                        icon: const Icon(Icons.how_to_reg_rounded),
                        label: const Text('Register'),
                      ),
                    ],
                  ],
                ),
              ),
              if ((pr['description'] as String).isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(pr['description'] as String, style: TextStyle(fontSize: 15.5, height: 1.5, color: cs.onSurface)),
              ],
              if (upcoming.isNotEmpty) ...[
                const SectionTitle('Next sessions'),
                ListCard(children: [for (final e in upcoming) _EventTile(e: e)]),
              ],
              SectionTitle('Resources', trailing: canEdit ? SeeAll(label: 'Add', onTap: addResource) : null),
              if (res.isEmpty)
                const Card(margin: EdgeInsets.zero, child: EmptyView('Notes and materials will appear here.', icon: Icons.folder_open_outlined))
              else
                ListCard(children: [
                  for (final r in res)
                    ListTile(
                      leading: Icon(r['url'].toString().contains('youtu') ? Icons.ondemand_video_rounded : Icons.description_outlined, color: cs.primary),
                      title: Text(r['title'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                      trailing: canEdit
                          ? IconButton(icon: const Icon(Icons.delete_outline_rounded), onPressed: () async {
                              if (await confirm(context, title: 'Remove "${r['title']}"?', action: 'Remove', danger: true)) {
                                await app.client.delete('public/programs/$id/resources/${r['id']}');
                                reload();
                              }
                            })
                          : const Icon(Icons.open_in_new_rounded, size: 18),
                      onTap: () => openLink(r['url'] as String),
                    ),
                ]),
              if (videos.isNotEmpty) ...[
                const SectionTitle('Past sessions'),
                for (final v in videos) _VideoCard(v: v),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ======================================================================= who's who

class WhosWhoScreen extends StatefulWidget {
  const WhosWhoScreen({super.key});
  @override
  State<WhosWhoScreen> createState() => _WhosWhoScreenState();
}

class _WhosWhoScreenState extends State<WhosWhoScreen> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text("Who's who"), actions: _publicActions(context)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: TextField(
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search name, wing or responsibility',
                prefixIcon: const Icon(Icons.search_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(99)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(99), borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          Expanded(
            child: Loader(
              load: () => app.client.get('public/whoswho'),
              builder: (context, d, reload) {
                bool match(Json p, [String wing = '']) => _q.isEmpty ||
                    '${p['name']} ${p['designation']} ${p['position']} $wing ${(p['responsibilities'] as List).join(' ')}'.toLowerCase().contains(_q);
                final bearers = (d['office_bearers'] as List).cast<Json>().where(match).toList();
                final wings = (d['wings'] as List).cast<Json>();
                var i = 0;
                return RefreshList(
                  onRefresh: reload,
                  children: [
                    if (bearers.isNotEmpty) ...[
                      const SectionTitle('Office bearers'),
                      Appear(index: i++, child: ListCard(children: [for (final p in bearers) _PersonRow(p: p, label: p['designation'] as String)])),
                    ],
                    for (final w in wings)
                      if ((w['people'] as List).cast<Json>().any((p) => match(p, w['name'] as String))) ...[
                        SectionTitle(w['name'] as String, trailing: Dot(colorOf(context, w))),
                        Appear(
                          index: i++,
                          child: ListCard(children: [
                            for (final p in (w['people'] as List).cast<Json>().where((p) => match(p, w['name'] as String)))
                              _PersonRow(p: p, label: (p['position'] as String).isNotEmpty ? p['position'] as String : 'Member'),
                          ]),
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

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.p, required this.label});
  final Json p;
  final String label;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final resp = (p['responsibilities'] as List).cast<String>();
    final highlight = label.isNotEmpty && label.toLowerCase() != 'member';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Initials(p['name'] as String, radius: 19),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p['name'] as String, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 3),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  Pill(label, tone: highlight ? 'brand' : 'neutral'),
                  if (p['member_type'] == 'executive') const Pill('Executive', tone: 'ghost'),
                ]),
                if (resp.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text('Responsible for: ${resp.join(', ')}', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ======================================================================= me / accounts

class PublicMeScreen extends StatelessWidget {
  const PublicMeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    if (app.api != null) return const ProfileScreen(root: true);
    return Scaffold(
      appBar: AppBar(title: const Text('Me')),
      body: RefreshList(
        onRefresh: () async {},
        children: [
          const SizedBox(height: 10),
          const Center(child: BrandMark(size: 96)),
          const SizedBox(height: 16),
          Text('Stay connected', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Register with your mobile number to receive announcements and updates from ${app.shortName}.',
              textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 24),
          FilledButton.icon(onPressed: () => push(context, const RegisterScreen()), icon: const Icon(Icons.how_to_reg_rounded), label: const Text('Register')),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: () => push(context, const LoginScreen()), child: const Text('Sign in')),
          const SizedBox(height: 6),
          TextButton(onPressed: () => showForgotPassword(context), child: const Text('Forgot password?')),
          const SizedBox(height: 40),
          // Members' invitation sign-in: available, but kept discreet.
          Center(
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
              onPressed: () => push(context, const LoginScreen(startWithInvite: true)),
              icon: const Icon(Icons.vpn_key_outlined, size: 16),
              label: const Text('Have an invite code?', style: TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showForgotPassword(BuildContext context) async {
  final app = AppScope.read(context);
  final phone = TextEditingController();
  await showSheet(context, title: 'Forgot password', builder: (ctx) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Enter your mobile number. Someone from the unit will send you a one-time code on WhatsApp or SMS; '
          'use it with "Have an invite code?" to choose a new password.',
          style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant, height: 1.4)),
      const SizedBox(height: 14),
      TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile number', prefixIcon: Icon(Icons.phone_outlined))),
      const SizedBox(height: 16),
      BusyButton(label: 'Request a reset', onPressed: () async {
        try {
          final msg = await app.requestPasswordReset(phone.text.trim());
          if (ctx.mounted) {
            Navigator.pop(ctx);
            toast(context, msg);
          }
        } on ApiException catch (e) {
          if (ctx.mounted) toast(ctx, e.message, error: true);
        }
      }),
      const SizedBox(height: 8),
      TextButton(onPressed: () {
        Navigator.pop(ctx);
        push(context, const LoginScreen(startWithInvite: true));
      }, child: const Text('I already have a code')),
    ],
  ));
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  bool _hide = true;
  ApiException? _error;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Register')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text('Get announcements, events and live sessions from ${app.shortName}.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 18),
          TextField(controller: _name, textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: 'Your name', prefixIcon: const Icon(Icons.person_outline_rounded), errorText: fieldError(_error, 'name'))),
          const SizedBox(height: 12),
          TextField(controller: _phone, keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: 'Mobile number', hintText: '+966 5x xxx xxxx', prefixIcon: const Icon(Icons.phone_outlined), errorText: fieldError(_error, 'phone'), errorMaxLines: 3)),
          const SizedBox(height: 12),
          TextField(controller: _pass, obscureText: _hide, autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(labelText: 'Password (8+ characters)', prefixIcon: const Icon(Icons.lock_outline_rounded), errorText: fieldError(_error, 'password'), errorMaxLines: 3,
                  suffixIcon: IconButton(icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined), onPressed: () => setState(() => _hide = !_hide)))),
          const SizedBox(height: 12),
          TextField(controller: _pass2, obscureText: _hide, decoration: const InputDecoration(labelText: 'Repeat password', prefixIcon: Icon(Icons.lock_outline_rounded))),
          const SizedBox(height: 22),
          BusyButton(label: 'Register', icon: Icons.how_to_reg_rounded, onPressed: () async {
            setState(() => _error = null);
            if (_pass.text != _pass2.text) {
              toast(context, 'The two passwords don\'t match.', error: true);
              return;
            }
            final nav = Navigator.of(context);
            try {
              await app.register(_name.text.trim(), _phone.text.trim(), _pass.text);
              nav.popUntil((r) => r.isFirst);
            } on ApiException catch (e) {
              setState(() => _error = e);
              if (context.mounted) toast(context, e.message, error: true);
            }
          }),
          const SizedBox(height: 12),
          Text('Your number is only used to sign in and is never shown publicly. See the privacy policy in the app menu.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _PublicInbox extends StatelessWidget {
  const _PublicInbox();
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Updates')),
      body: Loader(
        load: () => app.api!.get('notifications'),
        builder: (context, d, reload) {
          final items = (d['notifications'] as List).cast<Json>();
          return RefreshList(onRefresh: reload, children: [
            if (items.isEmpty) const EmptyView('Announcements and events will appear here.', icon: Icons.notifications_none_rounded),
            if (items.isNotEmpty)
              ListCard(children: [
                for (final n in items)
                  ListTile(
                    title: Text(n['title'] as String, style: TextStyle(fontWeight: n['read'] == true ? FontWeight.w500 : FontWeight.w800)),
                    subtitle: (n['body'] as String).isEmpty ? null : Text(n['body'] as String, maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: Text(ago(n['at'] as String?), style: const TextStyle(fontSize: 12)),
                    onTap: () {
                      app.api!.post('notifications/read', {'ids': [n['id']]}).then((r) => app.setCounts(r['counts'])).catchError((_) {});
                      if (n['kind'] == 'public' && n['object_id'] != null) push(context, PostDetailScreen(id: n['object_id'] as int));
                    },
                  ),
              ]),
          ]);
        },
      ),
    );
  }
}

// ======================================================================= editors (publishers)

class PostEditor extends StatefulWidget {
  const PostEditor({super.key, this.existing, this.kind});
  final Json? existing;
  final String? kind;
  @override
  State<PostEditor> createState() => _PostEditorState();
}

class _PostEditorState extends State<PostEditor> {
  late String _kind = (widget.existing?['kind'] as String?) ?? widget.kind ?? 'news';
  late final _title = TextEditingController(text: widget.existing?['title'] as String?);
  late final _body = TextEditingController(text: widget.existing?['body'] as String?);
  late final _place = TextEditingController(text: widget.existing?['location'] as String?);
  late final _link = TextEditingController(text: widget.existing?['link'] as String?);
  late String _cat = (widget.existing?['category'] as String?) ?? '';
  late int? _program = (widget.existing?['program'] as Json?)?['id'] as int?;
  DateTime? _start;
  DateTime? _end;
  bool _notify = true;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e?['starts_at'] != null) _start = DateTime.parse(e!['starts_at'] as String).toLocal();
    if (e?['ends_at'] != null) _end = DateTime.parse(e!['ends_at'] as String).toLocal();
    _notify = e == null;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final editing = widget.existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit post' : 'New public post'),
        actions: [
          if (editing)
            IconButton(icon: const Icon(Icons.delete_outline_rounded), onPressed: () async {
              final nav = Navigator.of(context);
              if (!await confirm(context, title: 'Delete this post?', action: 'Delete', danger: true)) return;
              await app.client.delete('public/posts/${widget.existing!['id']}');
              app.changed();
              nav.pop();
              if (nav.canPop()) nav.pop();
            }),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Segments<String>(
            items: const [('news', 'News'), ('event', 'Event'), ('live', 'Live'), ('video', 'Video')],
            value: _kind,
            onChanged: (v) => setState(() => _kind = v),
          ),
          const SizedBox(height: 14),
          TextField(controller: _title, textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: 'Title', errorText: fieldError(_error, 'title'))),
          const SizedBox(height: 12),
          if (_kind == 'live' || _kind == 'video' || _kind == 'event') ...[
            TextField(controller: _link, keyboardType: TextInputType.url,
                decoration: InputDecoration(labelText: _kind == 'event' ? 'Link (optional)' : 'YouTube / stream link', hintText: 'https://youtube.com/…', prefixIcon: const Icon(Icons.link_rounded), errorText: fieldError(_error, 'link'))),
            const SizedBox(height: 12),
          ],
          if (_kind == 'event' || _kind == 'live') ...[
            DateField(label: _kind == 'live' ? 'Starts (empty = now)' : 'Starts', withTime: true, value: _start, onChanged: (v) => setState(() => _start = v)),
            if (fieldError(_error, 'starts_at') != null)
              Padding(padding: const EdgeInsets.only(left: 12, top: 4), child: Text(fieldError(_error, 'starts_at')!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12))),
            const SizedBox(height: 12),
            DateField(label: 'Ends (optional)', withTime: true, value: _end, onChanged: (v) => setState(() => _end = v)),
            const SizedBox(height: 12),
          ],
          if (_kind == 'event') ...[
            TextField(controller: _place, decoration: const InputDecoration(labelText: 'Place (optional)', prefixIcon: Icon(Icons.place_outlined))),
            const SizedBox(height: 12),
          ],
          TextField(controller: _body, minLines: 3, maxLines: 10, textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Text (optional)', alignLabelWithHint: true)),
          if (_kind == 'video') ...[
            const SizedBox(height: 12),
            PickerField<String>(
              label: 'Category',
              value: _cat,
              placeholder: 'Choose…',
              groups: [PickGroup([for (final c in app.choice('video_categories')) PickOption(c['value'] as String, c['label'] as String)])],
              onChanged: (v) => setState(() => _cat = v ?? ''),
            ),
          ],
          const SizedBox(height: 12),
          Loader(
            load: () => app.client.get('public/programs'),
            builder: (context, d, _) {
              final progs = (d['programs'] as List).cast<Json>();
              if (progs.isEmpty) return const SizedBox.shrink();
              return PickerField<int?>(
                label: 'Programme (optional)',
                value: _program,
                placeholder: 'None',
                groups: [PickGroup([const PickOption<int?>(null, 'None'), for (final p in progs) PickOption<int?>(p['id'] as int, p['name'] as String)])],
                onChanged: (v) => setState(() => _program = v),
              );
            },
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Notify everyone with the app'),
            subtitle: const Text('Sends a notification to all phones that allowed them'),
            value: _notify,
            onChanged: (v) => setState(() => _notify = v),
          ),
          const SizedBox(height: 16),
          BusyButton(label: editing ? 'Save' : 'Publish', icon: Icons.public_rounded, onPressed: () async {
            setState(() => _error = null);
            final body = {
              'kind': _kind, 'title': _title.text, 'body': _body.text, 'link': _link.text, 'location': _place.text,
              'starts_at': _start == null ? null : isoDateTime(_start!), 'ends_at': _end == null ? null : isoDateTime(_end!),
              'category': _cat, 'program': _program, 'notify': _notify,
            };
            final nav = Navigator.of(context);
            try {
              editing ? await app.client.patch('public/posts/${widget.existing!['id']}', body) : await app.client.post('public/posts', body);
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

class ProgramEditor extends StatefulWidget {
  const ProgramEditor({super.key, this.existing});
  final Json? existing;
  @override
  State<ProgramEditor> createState() => _ProgramEditorState();
}

class _ProgramEditorState extends State<ProgramEditor> {
  late final _name = TextEditingController(text: (widget.existing?['name'] as String?) ?? 'QHLS — Quran, Hadith, Learning, School');
  late final _short = TextEditingController(text: (widget.existing?['short_name'] as String?) ?? 'QHLS');
  late final _desc = TextEditingController(text: widget.existing?['description'] as String?);
  late final _sched = TextEditingController(text: widget.existing?['schedule'] as String?);
  late final _place = TextEditingController(text: widget.existing?['location'] as String?);
  late final _reg = TextEditingController(text: widget.existing?['registration_url'] as String?);
  ApiException? _error;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final editing = widget.existing != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit programme' : 'New programme')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(controller: _name, decoration: InputDecoration(labelText: 'Name', errorText: fieldError(_error, 'name'))),
          const SizedBox(height: 12),
          TextField(controller: _short, decoration: const InputDecoration(labelText: 'Short name', hintText: 'QHLS')),
          const SizedBox(height: 12),
          TextField(controller: _sched, decoration: const InputDecoration(labelText: 'When', hintText: 'e.g. Every Friday after Isha', prefixIcon: Icon(Icons.event_repeat_rounded))),
          const SizedBox(height: 12),
          TextField(controller: _place, decoration: const InputDecoration(labelText: 'Where (optional)', prefixIcon: Icon(Icons.place_outlined))),
          const SizedBox(height: 12),
          TextField(controller: _reg, keyboardType: TextInputType.url,
              decoration: InputDecoration(labelText: 'Registration link (Google Form)', hintText: 'https://forms.gle/…', prefixIcon: const Icon(Icons.how_to_reg_outlined), errorText: fieldError(_error, 'registration_url'))),
          const SizedBox(height: 12),
          TextField(controller: _desc, minLines: 3, maxLines: 10, decoration: const InputDecoration(labelText: 'About (optional)', alignLabelWithHint: true)),
          const SizedBox(height: 24),
          BusyButton(label: editing ? 'Save' : 'Create', onPressed: () async {
            setState(() => _error = null);
            final body = {'name': _name.text, 'short_name': _short.text, 'description': _desc.text, 'schedule': _sched.text,
              'location': _place.text, 'registration_url': _reg.text};
            final nav = Navigator.of(context);
            try {
              editing ? await app.client.patch('public/programs/${widget.existing!['id']}', body) : await app.client.post('public/programs', body);
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
