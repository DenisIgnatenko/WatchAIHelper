#!/usr/bin/env bash
# Builds the backend on the Mac and deploys it to the Lightsail VM.
#  deploy/deploy.sh <STATIC_IP>
#
# What it does:
#  1. runs the tests and builds the jar (JDK 25);
#  2. creates the server .env on first deploy: secrets from backend/.env + a random DB password;
#  3. copies jar + Docker/Caddy config to /opt/aicopilot and restarts the stack;
#  4. waits until https://<IP>/actuator/health answers.
# Secrets travel only over SSH and are never written into git.
set -euo pipefail

IP="${1:?usage: deploy/deploy.sh <STATIC_IP>}"
KEY="${SSH_KEY:-$HOME/.ssh/aicopilot-lightsail.pem}"
SSH=(ssh -i "$KEY" -o StrictHostKeyChecking=accept-new "ubuntu@$IP")
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REMOTE=/opt/aicopilot
export JAVA_HOME="${JAVA_HOME_25:-/opt/homebrew/opt/openjdk@25}"

echo "== 1/4 Build and test"
# clean: a stale jar of an older version must never be picked up.
(cd "$ROOT/backend" && mvn -q clean verify)
JARS=("$ROOT"/backend/target/aicopilot-backend-*.jar)
[ "${#JARS[@]}" -eq 1 ] || { echo "Expected exactly one backend jar, found: ${JARS[*]}" >&2; exit 1; }
cp "${JARS[0]}" "$ROOT/deploy/app.jar"

echo "== 2/4 Server .env"
if ! "${SSH[@]}" "test -f $REMOTE/.env"; then
 # Only the keys the server needs; DB settings are container-internal.
 {
  grep -E '^(OPENAI_[A-Z0-9_]+|CLIENT_API_TOKEN|IMAGE_RETENTION_DAYS|ATTACHMENT_UPLOAD_TIMEOUT_MINUTES|USAGE_TIME_ZONE)=' "$ROOT/backend/.env"
  echo "DB_PASSWORD=$(openssl rand -hex 24)"
  echo "PUBLIC_IP=$IP"
 } | "${SSH[@]}" "umask 077 && cat > $REMOTE/.env"
 echo "created $REMOTE/.env"
else
 echo "kept existing $REMOTE/.env"
fi

echo "== 3/4 Upload and restart"
scp -i "$KEY" -q "$ROOT/deploy/app.jar" "$ROOT/deploy/Dockerfile" "$ROOT/deploy/docker-compose.yml" \
 "$ROOT/deploy/Caddyfile" "ubuntu@$IP:$REMOTE/"
rm -f "$ROOT/deploy/app.jar"
# Knowledge packs (third-party texts, not in git): copy if they were built locally with tools/knowledge.
"${SSH[@]}" "mkdir -p $REMOTE/knowledge"
if [ -d "$ROOT/knowledge" ]; then
 scp -i "$KEY" -q -r "$ROOT/knowledge/." "ubuntu@$IP:$REMOTE/knowledge/"
fi
"${SSH[@]}" "cd $REMOTE && docker compose up -d --build --remove-orphans && docker image prune -f >/dev/null"

echo "== 4/4 Health check (first start also obtains the TLS certificate)"
for _ in $(seq 1 100); do
 if curl -fsS "https://$IP/actuator/health" 2>/dev/null | grep -q UP; then
  echo "OK: https://$IP is up"
  exit 0
 fi
 sleep 3
done
echo "Backend did not become healthy. Logs: ssh ... 'cd $REMOTE && docker compose logs --tail 100'" >&2
exit 1
