# BizerOS operations runbook

The 5-minute reference for the operator running BizerOS client VMs. Each section is a problem the operator will hit, with the actual commands to fix it. See [README.md](./README.md) for the fresh-install path.

Default install path: `/opt/bizeros`. All commands assume root on the VM. If you're not root, prefix `sudo`.

---

## Routine: update an existing client VM

```
curl -fsSL https://raw.githubusercontent.com/kelsi-bizer/bizeros/develop/scripts/install-bizeros.sh \
  | sudo bash -s -- --update
```

Preserves `.env`, secrets, app data, and the existing Let's Encrypt cert. Pulls the latest `:nightly` image, recreates the runtipi container, re-renders the Traefik config (so any template changes in the new image apply), waits up to 90s for the cert to verify clean, then prints the dashboard URL.

The footer of every successful install run prints this exact command for next time, so you don't have to look it up.

---

## Where to look first

Order to check when something's wrong:

1. **Dashboard "Recent errors" card** at `https://dash.<client>.bizeros.com/dashboard` — surfaces the last 24h of backend errors. Green check = healthy. Red = look here first.
2. **Container logs:**
   ```
   cd /opt/bizeros
   docker compose -f docker-compose.bizeros.yml logs --tail=200 runtipi
   docker compose -f docker-compose.bizeros.yml logs --tail=200 runtipi-reverse-proxy
   ```
3. **Image revision:** confirm the container is on the SHA you expect.
   ```
   docker inspect ghcr.io/kelsi-bizer/bizeros:nightly \
     --format '{{.Created}} {{index .Config.Labels "org.opencontainers.image.revision"}}'
   ```
4. **Container health:**
   ```
   cd /opt/bizeros && docker compose -f docker-compose.bizeros.yml ps
   ```

---

## Forgot admin password

Recovery is via a 15-minute "password change request" flag file. Write it from inside the runtipi container, then open the dashboard.

```
docker exec runtipi sh -lc 'echo $(date +%s) > /data/state/password-change-request'
```

Then visit `https://dash.<client>.bizeros.com/reset-password` in a browser within 15 minutes and set a new password. The flag deletes itself once consumed.

If you wait too long, just re-run the `docker exec` to refresh the timestamp.

---

## Cert error (NET::ERR_CERT_AUTHORITY_INVALID, "served self-signed bizeros.local")

Three possible causes — check in this order:

1. **DNS not pointed at this VM.**
   ```
   dig +short dash.<client>.bizeros.com @1.1.1.1
   curl -fsS https://api.ipify.org && echo
   ```
   Both should print the same IP. If not, fix the A record at the registrar.

2. **Port 80 not reachable from the internet.** Let's Encrypt's HTTP-01 challenge needs to hit `http://dash.<client>.bizeros.com/.well-known/acme-challenge/...` from outside.
   ```
   ufw allow 80,443/tcp 2>/dev/null || true
   ```
   On Hostinger / most cloud hosts port 80 is open by default; on bare metal behind a NAT it isn't.

3. **Stale ACME state from a prior failed install.** Wipe and restart:
   ```
   cd /opt/bizeros
   docker compose -f docker-compose.bizeros.yml down
   rm -f .internal/traefik/shared/acme.json .internal/traefik/shared/acme-wildcard.json
   docker compose -f docker-compose.bizeros.yml up -d
   docker compose -f docker-compose.bizeros.yml logs -f runtipi-reverse-proxy 2>&1 | grep -iE 'acme|certificate'
   ```
   You should see `Adding certificate for domain(s) dash.<client>.bizeros.com` within 30 seconds.

---

## Restore an app from backup

Backups land at `/opt/bizeros/.internal/backups/<store>/<app>/<name>-<timestamp>.tar.gz`. The cron in PR #16 runs nightly at 03:00 (`BACKUP_CRON`, retention `MAX_BACKUPS=7` by default).

Restore via the dashboard:
1. Open the app's detail page in the dashboard.
2. Backups tab → pick a snapshot → Restore.

Restore via API (when the dashboard is down):
```
APP_URN="wordpress:bizeros"   # <appname>:<store>
FILE="wordpress-bizeros-1714782000000.tar.gz"
COOKIE="$(cat ~/.bizeros-session 2>/dev/null)"   # session cookie from a logged-in browser tab

curl -X POST "https://dash.<client>.bizeros.com/api/backups/$APP_URN/restore" \
  -H "Cookie: $COOKIE" \
  -H "Content-Type: application/json" \
  -d "{\"filename\":\"$FILE\"}"
```

Restore wipes the app's existing data dir and replaces it with the snapshot's contents. The app is stopped during restore and restarted afterwards (if it was running before).

---

## Copy backups off the VM

Backups on the VM are toast if the VM is. Copy them somewhere else — at minimum nightly:

```
rsync -av --delete /opt/bizeros/.internal/backups/ \
  user@backup-host:/srv/bizeros-backups/<client>/
```

Or pipe to a bucket:
```
aws s3 sync /opt/bizeros/.internal/backups/ s3://your-bucket/bizeros-backups/<client>/ --delete
```

Wire either as a host-side cron at 04:00 (after the BizerOS backup cron at 03:00 has finished).

---

## VM is dead / start fresh on a new VM

If you have backups copied off-VM (see above):

1. Provision the new VM.
2. Set DNS A records (`<client>.bizeros.com` and `*.<client>.bizeros.com`) to the new IP.
3. Run the standard fresh install: `curl ... | sudo bash -s -- --domain <client>.bizeros.com`.
4. Copy the snapshot tree back into `/opt/bizeros/.internal/backups/<store>/<app>/`.
5. For each app you want restored: install it once via the dashboard so the DB row exists, then use the Restore flow above.

If you have a snapshot of `/opt/bizeros/.internal` AND `/opt/bizeros/.env`:

1. Provision the new VM, install Docker.
2. Create `/opt/bizeros`, drop the snapshot tree in place (keep ownership/perms intact).
3. Run `--update`. The installer reads the existing `.env`, pulls the image, brings everything up.

Caveat: the new VM's public IP must be the same as the old, **or** DNS must be repointed before the cert renews.

---

## Disk filling up

Most likely culprits, in order:
1. **App data growth** — `du -sh /opt/bizeros/.internal/app-data/*/* | sort -h | tail`
2. **Backups too large** — drop `MAX_BACKUPS` in `.env` from 7 to a lower number, or move backups off-VM (see above).
3. **Docker images** — `docker system prune -a` (safe; recreates from registry on next `up`).
4. **Logs** — `du -sh /opt/bizeros/.internal/logs/*` ; truncate with `: > /opt/bizeros/.internal/logs/app.log` if needed.

---

## "Apps stopped working"

Quick triage:
```
cd /opt/bizeros
docker compose -f docker-compose.bizeros.yml ps
docker ps --filter label=runtipi.managed=true --format 'table {{.Names}}\t{{.Status}}'
```

If runtipi itself is unhealthy, restart it:
```
docker compose -f docker-compose.bizeros.yml restart runtipi
```

If specific apps are stuck:
```
docker compose --project-name <appname>_<store> \
  -f /opt/bizeros/.internal/apps/<store>/<appname>/docker-compose.generated.yml \
  --env-file /opt/bizeros/.internal/app-data/<store>/<appname>/app.env \
  up -d --force-recreate
```

Then check the dashboard's "Recent errors" card for the underlying cause.

---

## Reference: file layout on the host

```
/opt/bizeros/
├── .env                                 # secrets + config (chmod 600)
├── docker-compose.bizeros.yml           # top-level stack
└── .internal/
    ├── apps/<store>/<app>/              # per-app generated compose + config
    ├── app-data/<store>/<app>/          # per-app persistent data (volumes)
    │   └── app.env                      # per-app generated env
    ├── backups/<store>/<app>/           # nightly tar.gz snapshots
    ├── logs/                            # winston: app.log + error.log
    ├── repos/<id>/                      # cloned app stores
    ├── state/                           # firstboot flag, password-change request
    └── traefik/
        ├── traefik.yml                  # rendered from template at boot
        ├── shared/acme*.json            # Let's Encrypt account + certs
        └── tls/                         # local self-signed cert
```
