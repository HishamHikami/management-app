# Deploying on the droplet (Ubuntu 24.04 + nginx + systemd)

Same layout as `taskmanager` on this server. Run everything as root.

| What | Where |
|---|---|
| Code (root-owned) | `/srv/orgmanager` |
| Settings / secrets | `/etc/orgmanager/env` (root:root, 600) |
| Database + backups | `/var/lib/orgmanager` (app user only, 700) |
| Socket | `/run/orgmanager/gunicorn.sock` |
| Domain | `ksa-riyadh.halacreative.com` |

## 1. DNS
Create an `A` record for `ksa-riyadh.halacreative.com` pointing to the droplet's IP
(same as `tasks.halacreative.com`). Wait until `dig +short ksa-riyadh.halacreative.com` shows it.

## 2. User, code, settings

```bash
useradd --system --user-group --home-dir /var/lib/orgmanager --shell /usr/sbin/nologin orgmanager

# The repo is private: give the server a read-only deploy key.
ssh-keygen -t ed25519 -N '' -C 'droplet orgmanager' -f /root/.ssh/orgmanager_deploy
cat /root/.ssh/orgmanager_deploy.pub   # GitHub → repo → Settings → Deploy keys → Add (no write access)
cat >> /root/.ssh/config <<'CFG'
Host github-orgmanager
    HostName github.com
    User git
    IdentityFile /root/.ssh/orgmanager_deploy
    IdentitiesOnly yes
CFG
git clone git@github-orgmanager:HishamHikami/management-app.git /srv/orgmanager
cd /srv/orgmanager && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt

install -d -m 700 /etc/orgmanager
install -m 600 .env.example /etc/orgmanager/env
.venv/bin/python -c "import secrets; print(secrets.token_urlsafe(50))"   # paste as SECRET_KEY
nano /etc/orgmanager/env      # SECRET_KEY; the domain and Asia/Riyadh are already filled in
```

## 3. Services

```bash
cp deploy/orgmanager.service deploy/orgmanager-backup.service deploy/orgmanager-backup.timer \
   deploy/orgmanager-reminders.service deploy/orgmanager-reminders.timer /etc/systemd/system/
chmod 755 deploy/*.sh
systemctl daemon-reload
systemctl enable --now orgmanager                 # creates /var/lib/orgmanager and the socket
deploy/update.sh main                             # static files, migrations, restart, health check
deploy/manage.sh setup_org --name "Your Name" --email you@example.com --phone "+966..."
systemctl enable --now orgmanager-backup.timer orgmanager-reminders.timer
```

`setup_org` prints an invite code: open the app → **I have an invite code**.

## 4. nginx + HTTPS

```bash
cp deploy/nginx.conf.example /etc/nginx/sites-available/orgmanager
ln -s /etc/nginx/sites-available/orgmanager /etc/nginx/sites-enabled/orgmanager
nginx -t && systemctl reload nginx
certbot --nginx -d ksa-riyadh.halacreative.com
```

Check: `curl -s https://ksa-riyadh.halacreative.com/api/v1/config` returns the unit's name.

## Updating

```bash
/srv/orgmanager/deploy/update.sh main
```

Backs up the database, refuses code that adds GitHub workflows, pulls, installs, migrates,
restarts and checks `/health` and `/api/v1/config` answer.

## Backups
`orgmanager-backup.timer` writes a compressed copy to `/var/lib/orgmanager/backups` nightly at
02:45 (after taskmanager's 02:30) and keeps 14 days. Copy that folder off the server now and then.

Restore:
```bash
systemctl stop orgmanager
gunzip -c /var/lib/orgmanager/backups/db-YYYYMMDD-HHMMSS.sqlite3.gz > /var/lib/orgmanager/db.sqlite3
rm -f /var/lib/orgmanager/db.sqlite3-wal /var/lib/orgmanager/db.sqlite3-shm
chown orgmanager:orgmanager /var/lib/orgmanager/db.sqlite3
systemctl start orgmanager
```

## Memory
One gunicorn worker with 4 threads uses roughly 60–70 MB. The unit is capped at `MemoryHigh=150M`
/ `MemoryMax=250M`. The droplet had ~150 MB available when surveyed (23 Nov 2026), with swap in use,
so watch `free -h` after starting it; the largest user was `claude-rc` (~530 MB).

## Useful
```bash
journalctl -u orgmanager -f              # logs
deploy/manage.sh send_reminders          # send today's reminders now
deploy/manage.sh createsuperuser         # Django admin login at /admin/ (optional)
```
