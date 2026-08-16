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
docker compose up -d --build
docker image prune -f >/dev/null

# --- verify: fail the deploy if the API is not actually answering ---
for i in $(seq 30); do
  if curl -fsS --max-time 5 https://$DOMAIN/health >/dev/null; then
    echo "deploy ok: https://$DOMAIN/health"
    exit 0
  fi
  sleep 2
done
echo "health check failed after 60s" >&2
docker compose logs --tail=50 server >&2
exit 1
