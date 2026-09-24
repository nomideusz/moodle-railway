#!/bin/bash
# Railway entrypoint for Moodle: installed from the CLI on first boot with a generated
# admin password (the web installer is never reachable), upgraded from the CLI when
# the image brings a new release or plugin, Apache sized from the plan's memory, cron
# in the background, nightly backup to the Railway bucket.
set -euo pipefail

# Railway flattens the image layers, which brings back the mpm_event links the PHP
# image deleted, and Apache then refuses to start: "AH00534: More than one MPM
# loaded". mod_php needs prefork only.
rm -f /etc/apache2/mods-enabled/mpm_event.* /etc/apache2/mods-enabled/mpm_worker.*

# Prefork runs one process per concurrent request, and a Moodle page takes 20-60 MB of
# PHP memory. Budget 96 MB a worker after 384 MB for Apache, OPcache, cron and the
# backup job, sized from the plan's memory limit (Railway sets the cgroup limit to it),
# never from the host's 48 CPUs.
mem=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo max)
[ "$mem" = max ] && mem=$((8 << 30))
workers=$(( (mem / 1048576 - 384) / 96 ))
workers=${MOODLE_APACHE_WORKERS:-$(( workers < 4 ? 4 : workers > 64 ? 64 : workers ))}
printf '<IfModule mpm_prefork_module>\n\tMaxRequestWorkers %s\n</IfModule>\n' "$workers" \
  > /etc/apache2/conf-enabled/zz-workers.conf

: "${MOODLE_URL:?MOODLE_URL is not set: the site address, https://<your domain>}"
data=/var/moodledata
chown www-data: "$data"  # Railway mounts the volume owned by root

# Visitors get a "starting" page (503) until the install or upgrade below is done;
# without it, an empty database would open Moodle's web installer to anyone. A file
# that is already there means an admin turned maintenance on (moodle maintenance
# --enable): leave that one alone.
maint=
if [ ! -e "$data/climaintenance.html" ]; then
  install -o www-data -m 644 /usr/local/share/railway/maintenance.html "$data/climaintenance.html"
  maint=1
fi

trap 'kill $(jobs -p) 2>/dev/null; wait; exit 0' TERM INT
apache2-foreground &
apache_pid=$!

# On a fresh deploy Postgres may still be initializing. psql reads the PG* variables.
q() { psql -qtAX -v ON_ERROR_STOP=1 -c "$1"; }
for i in $(seq 90); do
  q 'select 1' >/dev/null 2>&1 && break
  [ "$i" = 90 ] && { echo "railway: database not reachable after 3 minutes"; exit 1; }
  sleep 2
done

# Moodle marks the install finished (rolesactive) at its very end. Tables without it
# are an install that was cut short, a redeploy during the first boot: no data yet,
# so clear them and start over.
if [ "$(q "select to_regclass('mdl_config') is not null")" = t ] &&
   [ "$(q "select count(*) from mdl_config where name = 'rolesactive' and value = '1'")" = 0 ]; then
  echo "railway: an earlier install did not finish; clearing it and starting over"
  q "select format('drop table %I cascade;', tablename) from pg_tables
     where schemaname = 'public' and tablename like 'mdl\_%'" | psql -q -v ON_ERROR_STOP=1 >/dev/null
fi
if [ "$(q "select to_regclass('mdl_config') is not null")" != t ]; then
  echo "railway: first boot, installing Moodle $MOODLE_VERSION (a minute or two)"
  moodle install_database --agree-license --lang=en --adminuser=admin \
    --adminpass="${MOODLE_ADMIN_PASSWORD:?MOODLE_ADMIN_PASSWORD is not set}" \
    --adminemail="${MOODLE_ADMIN_EMAIL:-admin@example.com}" --fullname=Moodle --shortname=Moodle \
    | { grep -v -e '^++ Success' -e '^-->' || true; }
fi

# A new release or plugin in the image: upgrade the database before serving it.
# --is-pending exits 2 when an upgrade is due.
rc=0; moodle upgrade --is-pending >/dev/null 2>&1 || rc=$?
if [ "$rc" = 2 ]; then
  echo "railway: upgrading the database to Moodle $MOODLE_VERSION and the plugins in the image"
  moodle upgrade --non-interactive | { grep -v -e '^++ Success' -e '^-->' || true; }
  moodle purge_caches
fi
[ -n "$maint" ] && rm -f "$data/climaintenance.html"
echo "railway: Moodle is up at $MOODLE_URL"

# Cron runs Moodle's scheduled and background tasks (email, grading, cleanup, course
# backups). Each run polls for new tasks for a few minutes. Task output is kept in
# Site administration > Server > Tasks > Task logs; only failures reach the log here.
while :; do
  moodle cron 2>&1 | grep -E 'task failed:|Fatal error|PHP (Warning|Notice)|^Warning:|Exception' || true
  sleep 60
done &

if [ -n "${S3_BUCKET:-}" ]; then
  # 03:00 UTC daily; a failed backup is logged, it never takes the site down.
  while sleep $(( (97200 - $(date +%s) % 86400) % 86400 )); do moodle-backup || true; done &
fi

# Apache exiting means the site is down: exit so Railway restarts the service.
wait -n "$apache_pid"
exit 1
