#!/usr/bin/env bash
# Minimal smoke test: build the image, run with a passwd-file overlay (no DB),
# verify it answers an IMAP CAPABILITY on 143.
set -euo pipefail

IMAGE="${IMAGE:-reference-dovecot:smoke}"
PORT="${PORT:-11143}"
NAME="reference-dovecot-smoke"

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  [ -n "${TMPDIR:-}" ] && rm -rf "$TMPDIR"
}
trap cleanup EXIT

TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/overlay/conf.d" "$TMPDIR/certs"

# Self-signed cert so dovecot's ssl=yes doesn't fail on missing files.
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$TMPDIR/certs/mail.smoke.test.key" \
    -out "$TMPDIR/certs/mail.smoke.test.crt" -days 1 -subj "/CN=mail.smoke.test" >/dev/null 2>&1

# Replace SQL auth with a single-user passwd-file so we don't need a DB to smoke-test.
cat >"$TMPDIR/overlay/conf.d/auth.conf" <<'EOF'
passdb {
  driver = passwd-file
  args = scheme=PLAIN /etc/dovecot/users
}
userdb {
  driver = passwd-file
  args = /etc/dovecot/users
}
EOF

# password is "smoke"
echo 'smoke@smoke.test:{PLAIN}smoke:5000:5000::/var/mail/vhosts/smoke.test/smoke::' \
    >"$TMPDIR/users"

# Override the rendered main config: drop SQL include implicitly by having our
# overlay auth.conf appear later — Dovecot conf.d files are read alphabetically,
# but we want auth.conf to fully replace SQL. Easiest: replace dovecot.conf
# with one that doesn't reference dovecot-sql.conf.ext at all.
cat >"$TMPDIR/overlay/dovecot.conf" <<'EOF'
protocols = imap
log_path = /dev/stderr
info_log_path = /dev/stdout
debug_log_path = /dev/stdout
listen = *
ssl = yes
ssl_cert = </certs/mail.smoke.test.crt
ssl_key = </certs/mail.smoke.test.key
ssl_min_protocol = TLSv1.2
auth_mechanisms = plain login
disable_plaintext_auth = no
mail_location = maildir:/var/mail/vhosts/%d/%n
mail_uid = 5000
mail_gid = 5000
first_valid_uid = 5000
last_valid_uid = 5000
!include conf.d/auth.conf
service imap-login {
  inet_listener imap {
    port = 143
  }
}
EOF

docker build -t "$IMAGE" .

docker run -d --name "$NAME" \
  -p "$PORT:143" \
  -e DOVECOT_HOSTNAME=mail.smoke.test \
  -e DOVECOT_DOMAIN=smoke.test \
  -v "$TMPDIR/overlay:/etc/dovecot-overlay:ro" \
  -v "$TMPDIR/users:/etc/dovecot/users:ro" \
  -v "$TMPDIR/certs:/certs:ro" \
  "$IMAGE"

# Wait for IMAP to answer.
ok=0
for i in $(seq 1 20); do
  if response=$( (echo "a CAPABILITY"; sleep 0.3) | nc -w 2 127.0.0.1 "$PORT" 2>/dev/null); then
    if echo "$response" | grep -q "^\* OK"; then
      ok=1
      break
    fi
  fi
  sleep 1
done

if [ "$ok" -ne 1 ]; then
  echo "FAIL: dovecot did not answer IMAP CAPABILITY on port $PORT"
  docker logs "$NAME" || true
  exit 1
fi

# Spot-check the banner mentions Dovecot.
if ! echo "$response" | grep -qi "dovecot\|IMAP4"; then
  echo "FAIL: unexpected IMAP banner: $response"
  docker logs "$NAME" || true
  exit 1
fi

echo "OK: dovecot answered IMAP CAPABILITY on port $PORT"
echo "$response" | head -3
