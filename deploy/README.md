# osb.gerege.mn deployment

Single-node Docker-runtime deployment of the OpenSandbox lifecycle server.

| Piece | Where |
|-------|-------|
| Checkout | `/opt/opensandbox` on the host (git remote = this fork) |
| Server | `docker compose` service `server`, host network, `127.0.0.1:8090` |
| TLS / proxy | nginx + Let's Encrypt on `osb.gerege.mn` |
| Sandbox ports | host `40000-41000`, returned to SDKs as `osb.gerege.mn:<port>` |
| Secrets | `deploy/.env` on the host (gitignored), `OPENSANDBOX_SERVER_API_KEY` |
| Metadata | docker volume `deploy_osb-data` → `/data/opensandbox.db` |

## CI/CD

`.github/workflows/deploy-osb-gerege.yml` runs on every push to `main` that
touches `server/**` or `deploy/**` (and on `workflow_dispatch`). It SSHes to the
host, `git reset --hard origin/main`, and runs `deploy/deploy.sh`, which rebuilds
the image, restarts the service, and fails the job if `https://osb.gerege.mn/health`
does not answer within 60s.

Repo secrets: `DEPLOY_HOST`, `DEPLOY_SSH_KEY`.

## Manual deploy

```bash
ssh root@osb.gerege.mn 'cd /opt/opensandbox && git pull && bash deploy/deploy.sh'
```

## Client usage

```bash
osb config set connection.domain osb.gerege.mn
osb config set connection.protocol https
osb config set connection.api_key <OPENSANDBOX_SERVER_API_KEY>
```
