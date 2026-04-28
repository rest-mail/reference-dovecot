# Changelog

Calver-tagged. Newest on top.

## 2026.04.28

- Initial release.
- Debian bookworm-slim + dovecot-core/imapd/pop3d/lmtpd/pgsql, supervised by tini.
- PID 1 is `dovecot -F` directly — no supervisord (single-process container).
- Overlay config via `/etc/dovecot-overlay/`:
  - `dovecot.conf` and `dovecot-sql.conf.ext` at the top level replace the rendered defaults.
  - `*.conf` and `conf.d/` are merged into `/etc/dovecot/conf.d/`.
- Env var templating (`envsubst`) on `dovecot.conf` and `dovecot-sql.conf.ext`.
- Env vars: `DOVECOT_HOSTNAME` (required), `DOVECOT_DOMAIN` (required),
  `DOVECOT_DB_{HOST,PORT,NAME,USER,PASSWORD}`, `DOVECOT_TLS_CERT`,
  `DOVECOT_TLS_KEY`, `DOVECOT_TLS_CA_PATH`, `DOVECOT_CA_NAME`,
  `DOVECOT_LOG_LEVEL`, `DOVECOT_AUTH_MECHANISMS`.
- CA trust: any `*.crt` under `DOVECOT_TLS_CA_PATH` is added to the system
  store under `${DOVECOT_CA_NAME}-ca.crt` (default `local-ca.crt`).
- Healthcheck: IMAP `CAPABILITY` against `127.0.0.1:143`.
- Multi-arch publish: linux/amd64, linux/arm64.
