FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        dovecot-core \
        dovecot-imapd \
        dovecot-pop3d \
        dovecot-lmtpd \
        dovecot-pgsql \
        ca-certificates \
        gettext-base \
        netcat-openbsd \
        tini \
    && rm -rf /var/lib/apt/lists/*

# Mail user (5000:5000). Documented; override in your own image if you need a different UID/GID.
RUN groupadd -g 5000 vmail && \
    useradd -g vmail -u 5000 vmail -d /var/mail/vhosts -s /usr/sbin/nologin && \
    mkdir -p /var/mail/vhosts /certs /etc/dovecot-overlay /etc/dovecot-defaults.tmpl && \
    chown -R vmail:vmail /var/mail/vhosts

COPY defaults/dovecot.conf /etc/dovecot-defaults.tmpl/dovecot.conf
COPY defaults/dovecot-sql.conf.ext /etc/dovecot-defaults.tmpl/dovecot-sql.conf.ext
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 143 993 110 995 24

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD echo "a CAPABILITY" | nc -w 1 127.0.0.1 143 | grep -q "^\* OK" || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
