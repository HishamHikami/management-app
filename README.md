# KSA Riyadh Unit — committees app

A self-hosted app for **Karnataka Riyadh Unit** to run its committees: the core committee assigns
work and speaks to everyone, committee heads run their teams, and every member sees what's theirs.

- **Android app** (Flutter) in [`mobile/`](mobile/README.md)
- **Server** (Django + SQLite) at the root of this repo — a JSON API for the app, plus Django admin

Built the same way as the `task-manager` app on the same server: light enough for a 1 GB droplet
shared with other sites (~60–70 MB RAM).

## What it does

| | |
|---|---|
| **Roles** | Admin · Core committee · Committee head · Member. A person can be in several committees. |
| **People** | Admins and the core committee add people and send a one-time **invite code** (e.g. on WhatsApp). The person chooses their own password in the app and signs in with their **email or phone number**. The same code flow resets a forgotten password. |
| **Tasks** | The core committee assigns to any committee or person; heads assign within their committee. Status (To do → In progress → Waiting → Done), priority, due date, reassign, and a timeline of comments and changes. |
| **Announcements** | To everyone, chosen committees, or chosen people. Pin, mark urgent, and ask people to **acknowledge** — the sender sees who has read and confirmed. |
| **Meetings** | General (everyone) or per committee. RSVP, add to calendar, map/online link, attendance, and minutes. |
| **Inbox & push** | Every update lands in the in-app inbox; with Firebase set up it also arrives as a phone notification. Daily morning reminders for meetings and due tasks. |

### Who can do what

| | Member | Head | Core | Admin |
|---|:-:|:-:|:-:|:-:|
| See own committees' tasks, meetings, announcements | ✓ | ✓ | ✓ (all) | ✓ (all) |
| Update status / comment on their committees' tasks | ✓ | ✓ | ✓ | ✓ |
| Create & assign tasks, call meetings, post announcements | | own committee | anywhere | anywhere |
| Post to everyone, call a general meeting, pin | | | ✓ | ✓ |
| Add people, add members to committees | | own committee (members only) | ✓ | ✓ |
| Appoint heads | | | ✓ | ✓ |
| Change the core committee, admins, deactivate people | | | | ✓ |

A separate **developer** account (`deploy/manage.sh set_developer <email|phone|#id>`) has full
access but is in no committee and hidden from the people list, announcements, meetings, pickers and
stats. Use your own normal account for your committee work.

## Try it locally

```bash
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env            # then set DEBUG=1 for local use
python manage.py migrate
python manage.py seed_demo      # example committees, people, tasks… (password is printed)
python manage.py runserver 0.0.0.0:8000
```

Point the app at it with `flutter run --dart-define=SERVER=http://<your-pc-ip>:8000`, or long-press
the logo on the sign-in screen to change the server.

Run tests: `python manage.py test org`

## First real setup

```bash
deploy/manage.sh migrate
deploy/manage.sh setup_org --name "Your Name" --email you@example.com --phone "+966 5x xxx xxxx"
```

This creates the core committee and you as admin, and prints an invite code. In the app tap
**I have an invite code**, choose your password, then add committees and people from the app.

## Deploy

See [deploy/DEPLOY.md](deploy/DEPLOY.md) — Ubuntu + nginx + systemd + certbot, same layout as the
other apps on the droplet. Push notifications: [docs/PUSH.md](docs/PUSH.md).

## Plan & next ideas

[docs/PLAN.md](docs/PLAN.md)
