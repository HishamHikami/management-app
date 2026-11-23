# KSA Riyadh Unit app — plan

## Decisions (23 Nov 2026)
- **Android first**, Flutter, same structure and look as `task-manager/mobile` (Material 3,
  themed picker sheets, per-tab navigation, fade-through tabs, haptics, pull-to-refresh, dark mode).
- **Server**: Django + SQLite (WAL) behind gunicorn/nginx on the existing droplet,
  `ksa-riyadh.halacreative.com`. PostgreSQL is installed there but SQLite keeps memory and
  backups simple; it comfortably handles a few hundred members.
- **Accounts**: admin invites with one-time codes; sign in with email or phone. English only.
- **Push**: Firebase Cloud Messaging, configured on the server (see PUSH.md). In-app inbox always.
- **Time zone**: Asia/Riyadh. **Colour**: deep teal `#0D6E6E` (one constant: `brand` in `mobile/lib/ui.dart`).
- Organization name and short name come from the server (`ORG_NAME`, `ORG_SHORT_NAME`).

## Data model
Member (1:1 Django user) · Committee (one `is_core`) · Membership (head/member, position) ·
Invite · ApiToken · Device · Task (+ assignees, TaskUpdate timeline) · Announcement (+ Receipt per
recipient: read/acknowledged) · Meeting (+ Attendee: RSVP/attendance, minutes) · Notification.

Recipients of announcements and meetings are fixed when they're sent, so people who join later
don't get old items, and read/attendance stats stay meaningful.

## Next ideas
1. **Attachments** on tasks, announcements and minutes (photos/PDFs) — stored under
   `/var/lib/orgmanager/media`, served by nginx.
2. **Polls** inside announcements (e.g. "How many from your family will attend?").
3. **Minutes → tasks**: turn action points into tasks in one tap.
4. **Monthly contributions** tracker for the Finance committee.
5. **Reports**: tasks per committee, attendance rates, overdue by committee.
6. **Web dashboard** for the core committee (same API).
7. **Arabic / Kannada** UI, iOS build.
