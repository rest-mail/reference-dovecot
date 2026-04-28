#!/bin/sh
set -eu

# ---------- env defaults ----------
: "${DOVECOT_HOSTNAME:?DOVECOT_HOSTNAME is required (e.g. mail.example.com)}"
: "${DOVECOT_DOMAIN:?DOVECOT_DOMAIN is required (e.g. example.com)}"

DOVECOT_DB_HOST="${DOVECOT_DB_HOST:-}"
DOVECOT_DB_PORT="${DOVECOT_DB_PORT:-5432}"
DOVECOT_DB_NAME="${DOVECOT_DB_NAME:-mail}"
DOVECOT_DB_USER="${DOVECOT_DB_USER:-mail}"
DOVECOT_DB_PASSWORD="${DOVECOT_DB_PASSWORD:-mail}"

DOVECOT_TLS_CERT="${DOVECOT_TLS_CERT:-/certs/${DOVECOT_HOSTNAME}.crt}"
DOVECOT_TLS_KEY="${DOVECOT_TLS_KEY:-/certs/${DOVECOT_HOSTNAME}.key}"
DOVECOT_TLS_CA_PATH="${DOVECOT_TLS_CA_PATH:-/certs/ca.d}"

DOVECOT_CA_NAME="${DOVECOT_CA_NAME:-local}"
DOVECOT_LOG_LEVEL="${DOVECOT_LOG_LEVEL:-info}"
DOVECOT_AUTH_MECHANISMS="${DOVECOT_AUTH_MECHANISMS:-plain login}"

OVERLAY_DIR="${DOVECOT_OVERLAY_DIR:-/etc/dovecot-overlay}"

export DOVECOT_HOSTNAME DOVECOT_DOMAIN \
       DOVECOT_DB_HOST DOVECOT_DB_PORT DOVECOT_DB_NAME DOVECOT_DB_USER DOVECOT_DB_PASSWORD \
       DOVECOT_TLS_CERT DOVECOT_TLS_KEY \
       DOVECOT_LOG_LEVEL DOVECOT_AUTH_MECHANISMS

# ---------- TLS / CA trust ----------
# Add any CA bundles in DOVECOT_TLS_CA_PATH to the system trust store under
# a neutral name keyed off DOVECOT_CA_NAME. Convention §8.
if [ -d "$DOVECOT_TLS_CA_PATH" ]; then
    i=0
    for ca in "$DOVECOT_TLS_CA_PATH"/*.crt; do
        [ -f "$ca" ] || continue
        if [ "$i" -eq 0 ]; then
            cp "$ca" "/usr/local/share/ca-certificates/${DOVECOT_CA_NAME}-ca.crt"
        else
            cp "$ca" "/usr/local/share/ca-certificates/${DOVECOT_CA_NAME}-ca-${i}.crt"
        fi
        i=$((i+1))
    done
    update-ca-certificates 2>/dev/null || true
fi
# Backward-compat: a single /certs/ca.crt is also honoured.
if [ -f /certs/ca.crt ] && [ ! -f "/usr/local/share/ca-certificates/${DOVECOT_CA_NAME}-ca.crt" ]; then
    cp /certs/ca.crt "/usr/local/share/ca-certificates/${DOVECOT_CA_NAME}-ca.crt"
    update-ca-certificates 2>/dev/null || true
fi

# ---------- render templates ----------
mkdir -p /etc/dovecot/conf.d
for f in /etc/dovecot-defaults.tmpl/*; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    envsubst < "$f" > "/etc/dovecot/$name"
done
chmod 600 /etc/dovecot/dovecot-sql.conf.ext 2>/dev/null || true
chown root:root /etc/dovecot/dovecot-sql.conf.ext 2>/dev/null || true

# ---------- merge overlay ----------
# Files in /etc/dovecot-overlay/ are dropped into /etc/dovecot/conf.d/.
# A file named dovecot.conf at the top level replaces the rendered main config.
if [ -d "$OVERLAY_DIR" ]; then
    if [ -f "$OVERLAY_DIR/dovecot.conf" ]; then
        cp "$OVERLAY_DIR/dovecot.conf" /etc/dovecot/dovecot.conf
    fi
    if [ -f "$OVERLAY_DIR/dovecot-sql.conf.ext" ]; then
        cp "$OVERLAY_DIR/dovecot-sql.conf.ext" /etc/dovecot/dovecot-sql.conf.ext
        chmod 600 /etc/dovecot/dovecot-sql.conf.ext
    fi
    # Anything else in the overlay (and any conf.d/ subdirectory) merges into conf.d.
    if [ -d "$OVERLAY_DIR/conf.d" ]; then
        cp -rf "$OVERLAY_DIR/conf.d/." /etc/dovecot/conf.d/ 2>/dev/null || true
    fi
    for f in "$OVERLAY_DIR"/*.conf; do
        [ -f "$f" ] || continue
        name=$(basename "$f")
        case "$name" in
            dovecot.conf) ;;
            *) cp "$f" "/etc/dovecot/conf.d/$name" ;;
        esac
    done
fi

# ---------- mail dir ----------
mkdir -p /var/mail/vhosts
chown -R vmail:vmail /var/mail/vhosts

# ---------- exec ----------
# Dovecot is PID 1 (under tini). SIGTERM = graceful, SIGHUP = reload+cert reload (native).
exec dovecot -F
