# PHP 8.4 (Moodle 5.2 needs 8.3+) on a fixed Debian release; PHP patch releases
# still come through. Moodle itself is pinned below: bump MOODLE_VERSION and its
# checksum deliberately, and the next start upgrades the site from the CLI.
FROM php:8.4-apache-trixie

# The extensions Moodle needs beyond the image's built-ins, Ghostscript for PDF
# annotation in assignments, and the Postgres client the backup job runs.
RUN set -eux; \
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends libfreetype-dev libicu-dev libjpeg62-turbo-dev libpng-dev libpq-dev libwebp-dev libxml2-dev libzip-dev; \
	docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
	docker-php-ext-install -j"$(nproc)" exif gd intl pgsql soap zip; \
	apt-mark auto '.*' > /dev/null; \
	apt-mark manual $savedAptMark > /dev/null; \
	find /usr/local -type f -name '*.so*' -exec ldd '{}' ';' \
		| awk '/=>/ { so = $(NF-1); if (index(so, "/usr/local/") == 1) { next }; gsub("^/(usr/)?", "", so); printf "*%s\n", so }' \
		| sort -u | xargs -r dpkg-query --search | cut -d: -f1 | sort -u | xargs -rt apt-mark manual; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	apt-get install -y --no-install-recommends ghostscript postgresql-client; \
	rm -rf /var/lib/apt/lists/*; \
	php -m | grep -qx sodium; php -m | grep -qx intl

# The official release package. The code stays in the image, owned by root: only
# the data directory is on the volume, which keeps it small and makes an upgrade a
# plain redeploy. Plugins are added to the image from plugins/ (see its README).
ENV MOODLE_VERSION=5.2.3
RUN set -eux; \
	curl -fsSL -o /tmp/moodle.tgz "https://packaging.moodle.org/stable502/moodle-${MOODLE_VERSION}.tgz"; \
	echo '918c4bed6639056d1a3fcca37747ad95c4ec988024d2ef6b662897bcee55a581  /tmp/moodle.tgz' | sha256sum -c -; \
	mkdir -p /var/www/moodle; \
	tar -xzf /tmp/moodle.tgz -C /var/www/moodle --strip-components=1 --no-same-owner; \
	rm /tmp/moodle.tgz
# The PHP libraries Moodle lists in composer.json, installed the way its install
# guide says (without them, Environment reports "Composer dependencies were not found").
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer
RUN set -eux; \
	cd /var/www/moodle; \
	COMPOSER_ALLOW_SUPERUSER=1 COMPOSER_HOME=/tmp/composer composer install --no-dev --classmap-authoritative --no-interaction --no-progress; \
	rm -rf /usr/local/bin/composer /tmp/composer
COPY config.php /var/www/moodle/
COPY plugins/ /var/www/moodle/public/
RUN php -l /var/www/moodle/config.php

# Moodle's recommended PHP settings; OPcache has to hold ~50,000 files.
RUN printf '%s\n' 'memory_limit = 256M' 'upload_max_filesize = 256M' 'post_max_size = 256M' \
		'max_execution_time = 300' 'max_input_vars = 5000' 'expose_php = Off' 'zend.exception_ignore_args = On' \
		'opcache.memory_consumption = 128' 'opcache.max_accelerated_files = 65407' 'opcache.revalidate_freq = 60' \
	> /usr/local/etc/php/conf.d/moodle.ini

# Apache on Railway's $PORT, IPv6 and IPv4 (the [::] socket takes both where it can,
# and Apache falls back to IPv4 alone on hosts without IPv6). Errors go to stdout:
# Railway paints all of stderr red, including Apache's startup notices.
ENV PORT=8080
RUN set -eux; \
	printf 'Listen [::]:${PORT}\nListen 0.0.0.0:${PORT}\n' > /etc/apache2/ports.conf; \
	ln -sfT /dev/stdout /var/log/apache2/error.log; \
	sed -i 's/^ServerTokens OS/ServerTokens Prod/; s/^ServerSignature On/ServerSignature Off/' /etc/apache2/conf-available/security.conf; \
	mkdir -p /usr/local/share/railway /var/moodledata; \
	echo ok > /usr/local/share/railway/healthz
# Moodle's router also takes paths ending in .php that are not files; the image's
# PHP handler would answer those with a 404 before FallbackResource sees them.
RUN sed -i 's|^\tSetHandler application/x-httpd-php$|\t<If "-f %{REQUEST_FILENAME}">\n\t\tSetHandler application/x-httpd-php\n\t</If>|' /etc/apache2/conf-available/docker-php.conf; \
	grep -q 'If "-f' /etc/apache2/conf-available/docker-php.conf
COPY moodle.conf /etc/apache2/sites-available/000-default.conf
COPY maintenance.html /usr/local/share/railway/

# The visitor's address: Railway's edge connects from 100.64.0.0/10 and sets X-Real-IP
# to the client (overwriting what the client sent). X-Forwarded-For ends in an edge
# hop, so trusting it would log the proxy for everyone.
RUN printf '%s\n' 'RemoteIPHeader X-Real-IP' 'RemoteIPInternalProxy 100.64.0.0/10' > /etc/apache2/conf-available/remoteip.conf; \
	a2enmod remoteip >/dev/null; a2enconf remoteip >/dev/null

COPY --chmod=0755 moodle moodle-backup moodle-restore /usr/local/bin/
COPY --chmod=0755 railway-entrypoint.sh /railway-entrypoint.sh
WORKDIR /var/www/moodle
ENTRYPOINT ["/railway-entrypoint.sh"]
# The PHP image stops Apache with SIGWINCH; the entrypoint handles SIGTERM, which is
# also what Railway sends.
STOPSIGNAL SIGTERM
