import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../state.dart';
import '../ui.dart';
import 'committees.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, this.root = false});
  final bool root;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final me = app.me;
    final committees = ((me['committees'] as List?) ?? []).cast<Json>();
    final role = app.isDeveloper
        ? 'Developer'
        : app.isPublic
        ? 'Registered'
        : app.isSuper
        ? 'Super admin'
        : app.isCore
        ? 'Admin'
        : me['member_type'] == 'executive'
        ? 'Executive'
        : 'Member';
    return Scaffold(
      appBar: AppBar(title: Text(root ? 'Me' : 'Profile')),
      body: RefreshList(
        onRefresh: app.refreshBoot,
        children: [
          Center(child: Hero(tag: 'me-avatar', child: Initials((me['name'] as String?) ?? '?', radius: 42))),
          const SizedBox(height: 12),
          Text((me['name'] as String?) ?? '', textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Center(child: Pill(role, tone: 'brand', icon: Icons.verified_user_outlined)),
          const SizedBox(height: 18),
          ListCard(
            children: [
              if (!app.isPublic) ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit my details'),
                subtitle: Text([me['phone'], me['email']].where((s) => (s as String?)?.isNotEmpty == true).join(' · ')),
                onTap: () async {
                  await push(context, PersonEditor(existing: me));
                  app.refreshBoot();
                },
              ),
              ListTile(
                leading: const Icon(Icons.lock_outline_rounded),
                title: const Text('Change password'),
                onTap: () => _changePassword(context),
              ),
              if (!app.isPublic) ListTile(
                leading: const Icon(Icons.groups_outlined),
                title: const Text('My wings'),
                subtitle: Text(committees.isEmpty
                    ? 'None yet'
                    : committees.map((c) => ((c['position'] as String?) ?? '').isEmpty ? c['name'] : '${c['name']} (${c['position']})').join(', ')),
                onTap: () => push(context, MemberDetailScreen(id: app.meId)),
              ),
              ListTile(
                leading: Icon(app.boot?['push'] == true ? Icons.notifications_active_outlined : Icons.notifications_off_outlined),
                title: const Text('Phone notifications'),
                subtitle: Text(app.boot?['push'] == true
                    ? 'On — you get new tasks, announcements and meetings instantly'
                    : 'Not set up on the server yet — check the Inbox for updates'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ListCard(
            children: [
              ListTile(
                leading: const BrandMark(size: 36),
                title: Text(app.orgName),
                subtitle: Text('${app.shortName} app · ${app.server.replaceFirst('https://', '')}'),
              ),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Privacy policy'),
                trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                onTap: () => launchUrl(Uri.parse('${app.server}/privacy'), mode: LaunchMode.externalApplication),
              ),
            ],
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: cs.error, side: BorderSide(color: cs.error.withValues(alpha: .5))),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
            onPressed: () async {
              if (await confirm(context, title: 'Sign out?', action: 'Sign out')) {
                if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                await app.logout();
              }
            },
          ),
          if (!app.isDeveloper) ...[
            const SizedBox(height: 8),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: cs.error),
              onPressed: () => _deleteAccount(context),
              child: const Text('Delete my account'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final app = AppScope.read(context);
    final pass = TextEditingController();
    await showSheet(
      context,
      title: 'Delete my account',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Your name, phone, email and password are removed and you are signed out on every phone. '
            'Tasks, announcements and minutes you wrote stay for the unit, shown as "Former member". '
            'This can\'t be undone; an admin can invite you again later.',
            style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 14),
          TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'Your password')),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error, foregroundColor: Theme.of(ctx).colorScheme.onError),
            onPressed: () async {
              try {
                await app.deleteAccount(pass.text);
                if (ctx.mounted) Navigator.of(ctx).popUntil((r) => r.isFirst);
              } on ApiException catch (e) {
                if (ctx.mounted) toast(ctx, e.message, error: true);
              }
            },
            child: const Text('Delete my account permanently'),
          ),
        ],
      ),
    );
  }

  Future<void> _changePassword(BuildContext context) async {
    final app = AppScope.read(context);
    final old = TextEditingController();
    final new1 = TextEditingController();
    final new2 = TextEditingController();
    await showSheet(
      context,
      title: 'Change password',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(controller: old, obscureText: true, decoration: const InputDecoration(labelText: 'Current password')),
          const SizedBox(height: 12),
          TextField(controller: new1, obscureText: true, decoration: const InputDecoration(labelText: 'New password (8+ characters)')),
          const SizedBox(height: 12),
          TextField(controller: new2, obscureText: true, decoration: const InputDecoration(labelText: 'Repeat new password')),
          const SizedBox(height: 16),
          BusyButton(
            label: 'Change password',
            onPressed: () async {
              if (new1.text != new2.text) {
                toast(ctx, 'The new passwords don\'t match.', error: true);
                return;
              }
              try {
                await app.api!.post('auth/password', {'old_password': old.text, 'new_password': new1.text});
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  toast(context, 'Password changed. Other phones were signed out.');
                }
              } on ApiException catch (e) {
                if (ctx.mounted) toast(ctx, e.message, error: true);
              }
            },
          ),
        ],
      ),
    );
  }
}
