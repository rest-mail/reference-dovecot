# reference-dovecot

A small, generic [Dovecot](https://www.dovecot.org/) container with overlay-config support and env-var templating. Debian bookworm-slim base, `dovecot -F` as PID 1 under `tini`, multi-arch (`linux/amd64` + `linux/arm64`), MIT.

Useful as a standalone IMAP/POP3/LMTP server for development or as the mailstore layer of a larger mail stack. No assumptions about your auth backend, your domain, or your TLS — supply them via env vars or overlay.

## Image

```
ghcr.io/rest-mail/reference-dovecot:latest          # always newest
ghcr.io/rest-mail/reference-dovecot:YYYY.MM.DD      # immutable calver tag
```

## Quick start (standalone)

```bash
docker run --rm \
  -e DOVECOT_HOSTNAME=mail.example.com \
  -e DOVECOT_DOMAIN=example.com \
  -e DOVECOT_DB_HOST=postgres \
  -e DOVECOT_DB_NAME=mail \
  -e DOVECOT_DB_USER=mail \
  -e DOVECOT_DB_PASSWORD=secret \
  -p 143:143 -p 993:993 -p 110:110 -p 995:995 -p 24:24 \
  -v $(pwd)/certs:/certs:ro \
  ghcr.io/rest-mail/reference-dovecot:latest
```

The image expects:
- A TLS cert at `/certs/${DOVECOT_HOSTNAME}.crt` and key at `.key` (override with `DOVECOT_TLS_CERT` / `DOVECOT_TLS_KEY`).
- A reachable Postgres with the schema described in `defaults/dovecot-sql.conf.ext`. Replace the SQL config via overlay if your schema differs.

## Overlay config

Drop files in `/etc/dovecot-overlay/`:

| Path in overlay | Effect |
|-----------------|--------|
| `dovecot.conf` | Replaces the rendered main config wholesale. |
| `dovecot-sql.conf.ext` | Replaces the SQL passdb/userdb config. |
| `*.conf` (other) | Copied into `/etc/dovecot/conf.d/`. |
| `conf.d/...` | Merged into `/etc/dovecot/conf.d/`. |

Example — switch to a passwd-file backend without rebuilding:

```bash
mkdir -p overlay/conf.d
cat > overlay/conf.d/auth.conf <<'EOF'
passdb {
  driver = passwd-file
  args = scheme=PLAIN /etc/dovecot/users
}
userdb {
  driver = passwd-file
  args = /etc/dovecot/users
}
EOF
docker run --rm \
  -e DOVECOT_HOSTNAME=mail.example.com \
  -e DOVECOT_DOMAIN=example.com \
  -v $(pwd)/overlay:/etc/dovecot-overlay:ro \
  -v $(pwd)/users:/etc/dovecot/users:ro \
  -v $(pwd)/certs:/certs:ro \
  -p 143:143 \
  ghcr.io/rest-mail/reference-dovecot:latest
```

## Environment variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DOVECOT_HOSTNAME` | yes | — | Server's own hostname; also default cert filename. |
| `DOVECOT_DOMAIN` | yes | — | Primary mail domain (used in `postmaster_address`). |
| `DOVECOT_DB_HOST` | no | (empty) | Postgres host for SQL passdb/userdb. |
| `DOVECOT_DB_PORT` | no | `5432` | Postgres port. |
| `DOVECOT_DB_NAME` | no | `mail` | Postgres database name. |
| `DOVECOT_DB_USER` | no | `mail` | Postgres user. |
| `DOVECOT_DB_PASSWORD` | no | `mail` | Postgres password. |
| `DOVECOT_TLS_CERT` | no | `/certs/$DOVECOT_HOSTNAME.crt` | TLS cert path inside container. |
| `DOVECOT_TLS_KEY` | no | `/certs/$DOVECOT_HOSTNAME.key` | TLS key path inside container. |
| `DOVECOT_TLS_CA_PATH` | no | `/certs/ca.d` | Directory of additional CA certs to install into the system trust store. |
| `DOVECOT_CA_NAME` | no | `local` | Filename prefix used when installing CAs (`${DOVECOT_CA_NAME}-ca.crt`). |
| `DOVECOT_LOG_LEVEL` | no | `info` | Reserved for future use; currently informational only. |
| `DOVECOT_AUTH_MECHANISMS` | no | `plain login` | Value for `auth_mechanisms` in the rendered config. |
| `DOVECOT_OVERLAY_DIR` | no | `/etc/dovecot-overlay` | Where to look for overlay config files. |

The DB defaults (`mail`/`mail`/`mail`) are deliberately neutral — the image makes **no** assumptions about a `restmail` schema, user, or password. They exist only so you can boot the container without setting every variable when wiring up a quick local Postgres for experimentation.

## Healthcheck

```bash
echo "a CAPABILITY" | nc -w 1 127.0.0.1 143 | grep -q "^\* OK"
```

A successful response means the IMAP login service is up and answering. Configured via `HEALTHCHECK` in the Dockerfile (interval 30s, timeout 5s, start-period 10s, retries 3).

## Signals

- **SIGTERM** → graceful shutdown (handled by `tini` + Dovecot).
- **SIGHUP** → reload config and TLS certs without restart (native Dovecot behaviour). Required for cert-rotation flows.

## User and ports

- Process runs as `root` so Dovecot can bind privileged ports and switch UIDs per its master process model. Mail processes drop to `vmail` (UID:GID `5000:5000`).
- Exposed: `143` (IMAP), `993` (IMAPS), `110` (POP3), `995` (POP3S), `24` (LMTP).
- The auth service additionally listens on `12345` for SASL clients (e.g. an MTA).

## Layout

```
.
├── Dockerfile
├── entrypoint.sh
├── defaults/
│   ├── dovecot.conf            # baked-in defaults; overlay overrides
│   └── dovecot-sql.conf.ext    # SQL passdb/userdb template
├── .github/workflows/
│   └── build.yml               # multi-arch GHCR publish on push to master
└── tests/
    └── smoke.sh                # spin up + IMAP CAPABILITY + verify
```

## Building locally

```bash
docker build -t reference-dovecot:dev .
./tests/smoke.sh                 # builds and runs the smoke test
```

## License

MIT.

## See also

- [`rest-mail/conventions`](https://github.com/rest-mail/conventions) — the contract every `reference-*` image follows (overlay paths, env var naming, signal handling, calver tagging).
- [`rest-mail/reference-postfix`](https://github.com/rest-mail/reference-postfix) — pairs naturally with this image as the MTA half of a small mail stack.
- [`rest-mail/testbed`](https://github.com/rest-mail/testbed) — composes this image alongside `reference-postfix`, `reference-rspamd`, `reference-dnsmasq`, and `reference-certgen` into a full local-internet mail sandbox.
