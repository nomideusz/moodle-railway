# Deploy and Host Moodle on Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/moodle-5?utm_medium=integration&utm_source=button&utm_campaign=moodle-5)

[Moodle](https://moodle.org) is the open-source learning platform used by schools, universities and companies worldwide: courses, assignments, quizzes, gradebook, forums, badges and certificates, with more than 2,000 plugins. This template runs the current official Moodle 5.2 release (5.2.3) on PostgreSQL.

## About Hosting Moodle

Two services and a bucket:

- **Moodle** runs PHP 8.4 and Apache with the official release package. The code is in the image; uploaded files, the site secret and caches live on the volume at `/var/moodledata`. Cron runs in the same service every minute, so scheduled tasks, emails and course backups work without extra setup.
- **Postgres** 17, reachable only over Railway's private network.
- **Backups** is a Railway bucket that gets a nightly copy of the database and the data directory.

Moodle is installed from the command line on first boot, with an admin password generated at deploy. The web installer is never reachable: until the install finishes, the site shows a "Moodle is starting" page.

## Common Use Cases

- An online school or course platform with enrolments, assignments, quizzes and grades
- Staff training and onboarding with completion tracking and certificates
- A course site for a single teacher, a tutoring business or a community

## Dependencies for Moodle Hosting

- A PostgreSQL database (included)
- An SMTP server for email (optional; see below)

### Deployment Dependencies

- [Moodle documentation](https://docs.moodle.org/502/en/Main_page)
- [Moodle plugins directory](https://moodle.org/plugins/)
- [Template source on GitHub](https://github.com/nomideusz/moodle-railway)

### Implementation Details

**After deploying:** the first deploy takes about five minutes: about four to build the image and one to install Moodle. Then open the Moodle domain and log in as `admin` with `MOODLE_ADMIN_PASSWORD` from the Moodle service's Variables tab. Change the site name under Site administration → General → Site home settings, and the admin email in the admin's profile.

**Email.** Set up SMTP under Site administration → Server → Email → Outgoing mail configuration. Railway allows outbound SMTP only on the Pro plan and above; on Trial and Hobby, Moodle can't send email (Moodle has no HTTP-API mail option).

**Custom domain.** Add it in the service's Networking settings, then set `MOODLE_URL` to `https://your.domain`. Links already stored in course content still point to the old address; the "Search and replace" tool under Site administration → Development fixes those.

**Plugins.** The code is part of the image, so plugins are added there too and survive every redeploy. Fork the [template repository](https://github.com/nomideusz/moodle-railway), put each plugin under `plugins/` at the path Moodle expects (for example `plugins/mod/attendance`), point the service at your fork and redeploy. The next start installs the plugin. Installing plugins from the admin page is turned off because the image is read-only.

**Updates.** Bump `MOODLE_VERSION` and its checksum in the `Dockerfile` and redeploy. The start script runs Moodle's command-line upgrade before serving the new release, and visitors see the "starting" page while it runs. Take a backup first (below).

**Backups.** Every night at 03:00 UTC the database dump and the data directory (without caches) go to the Backups bucket as `moodle-<Weekday>.tar.gz`, so the last seven days are kept. Run `moodle-backup` from `railway ssh` for an extra one before a risky change, and `moodle-restore Mon` to restore the backup of that day. Clear `S3_BUCKET` to turn nightly backups off.

**Command line.** `moodle <script>` runs any of Moodle's CLI scripts as the web server user, for example `moodle purge_caches`, `moodle maintenance --enable` or `moodle reset_password`.

**Memory.** Apache's worker count follows the service's memory limit: 6 workers at 1 GB, up to 64 on large plans. Moodle idles at about 100 MB. In testing, 16 users clicking at once took it to about 230 MB with a 1 GB limit, and to about 0.75 GB on an 8 GB plan, where Apache starts more workers. Postgres uses 0.1–0.3 GB.

**Changes from a stock Moodle install:**

- Only `public/` is served, and the internal files that Moodle's security guide says to hide return 403.
- Moodle's router is configured (paths that aren't files go to `r.php`), so the router checks pass.
- Visitors' real IP addresses come from Railway's edge (`X-Real-IP`), so logs, login throttling and IP-based rules see the client and not the proxy.
- Composer dependencies are installed the way the Moodle install guide says, so the Environment page is clean.

## Why Deploy Moodle on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying Moodle on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.
