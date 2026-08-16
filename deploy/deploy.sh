#!/usr/bin/env bash
# Deploy the OpenSandbox server on osb.gerege.mn. Idempotent; run from anywhere.
# Called by CI over SSH and safe to run by hand.
set -euo pipefail

DOMAIN=osb.gerege.mn
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

[ -f .env ] || { echo "deploy/.env missing (needs OPENSANDBOX_SERVER_API_KEY)" >&2; exit 1; }

# --- nginx: snippet is repo-owned, site file is certbot-owned after first run ---
install -D -m 644 nginx-proxy.conf /etc/nginx/snippets/osb-proxy.conf
if [ ! -f /etc/nginx/sites-available/$DOMAIN ]; then
  install -m 644 nginx-site.conf /etc/nginx/sites-available/$DOMAIN
  ln -sfn /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/$DOMAIN
  rm -f /etc/nginx/sites-enabled/default
fi
nginx -t && systemctl reload nginx

# --- TLS: issue once, certbot.timer handles renewals ---
if [ ! -d /etc/letsencrypt/live/$DOMAIN ]; then
  certbot --nginx -d $DOMAIN --non-interactive --agree-tos \
    -m "${CERTBOT_EMAIL:-admin@gerege.mn}" --redirect
fi

# --- app ---
mkdir -p /srv/opensandbox-volumes
docker compose up -d --build

# Pre-pull sandbox images so the first user does not wait on a registry pull.
for image in opensandbox/execd:v1.0.22 opensandbox/egress:v1.1.6 \
             opensandbox/code-interpreter:v1.1.0 python:3.12-slim; do
  docker image inspect "$image" >/dev/null 2>&1 || docker pull -q "$image"
done
docker image prune -f >/dev/null

# --- verify: fail the deploy if the API is not actually answering ---
ok=
for i in $(seq 30); do
  if curl -fsS --max-time 5 https://$DOMAIN/health >/dev/null; then ok=1; break; fi
  sleep 2
done
[ -n "$ok" ] || { echo "health check failed after 60s" >&2; docker compose logs --tail=50 server >&2; exit 1; }

# smoke test: a real sandbox must come up through TLS + auth, then be removed
. ./.env
smoke() { curl -fsS --max-time 120 -H "OPEN-SANDBOX-API-KEY: $OPENSANDBOX_SERVER_API_KEY" "$@"; }
sid=$(smoke -X POST https://$DOMAIN/sandboxes -H 'Content-Type: application/json' \
  -d '{"image":{"uri":"python:3.12-slim"},"entrypoint":["sleep","60"],"timeout":60,"resourceLimits":{"cpu":"1","memory":"512Mi"}}' \
  | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
[ -n "$sid" ] || { echo "smoke test: sandbox create failed" >&2; exit 1; }
smoke -X DELETE "https://$DOMAIN/sandboxes/$sid" >/dev/null

echo "deploy ok: https://$DOMAIN (health + sandbox smoke test passed)"
