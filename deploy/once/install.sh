#!/usr/bin/env bash
#
# Beams ONCE installer.
#
# Installs and starts Beams as a single Docker container on a fresh Linux host.
# Run as root (or via sudo). Requires Docker to be installed.
#
# Usage:
#   RAILS_MASTER_KEY=xxxxxxxx [TLS_DOMAIN=beams.example.com] sudo -E bash deploy/once/install.sh
#
# RAILS_MASTER_KEY is required. TLS_DOMAIN is optional: when set, Thruster
# terminates HTTPS on 443 via Let's Encrypt; when unset, only HTTP (80) is served.

set -euo pipefail

# --- Shared constants (MUST stay in sync with lib/beams/once/updater.rb) ------
IMAGE="${IMAGE:-ghcr.io/REPLACE_ME/beams:latest}"
CONTAINER="beams"
VOLUME="beams_storage"
MOUNT="/rails/storage"
ENV_DIR="/etc/beams"
ENV_FILE="${ENV_DIR}/beams.env"
HTTP_PORT="80:80"
HTTPS_PORT="443:443"
RESTART_POLICY="unless-stopped"
# ------------------------------------------------------------------------------

echo "==> Beams ONCE installer"
echo "    Requirements: Linux + Docker. Run as root (or via sudo)."
echo "    Image: ${IMAGE}"

# 1. Docker must be present.
if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: 'docker' command not found." >&2
  echo "       Install Docker first: https://docs.docker.com/engine/install/" >&2
  exit 1
fi

# 2. RAILS_MASTER_KEY is mandatory; TLS_DOMAIN is optional.
if [ -z "${RAILS_MASTER_KEY:-}" ]; then
  echo "ERROR: RAILS_MASTER_KEY is not set." >&2
  echo "       Re-run with: RAILS_MASTER_KEY=<key> sudo -E bash deploy/once/install.sh" >&2
  exit 1
fi

TLS_DOMAIN="${TLS_DOMAIN:-}"
if [ -n "${TLS_DOMAIN}" ]; then
  echo "==> TLS_DOMAIN=${TLS_DOMAIN} (HTTPS on 443 via Let's Encrypt)"
else
  echo "==> TLS_DOMAIN not set (HTTP only on 80)"
fi

# 3. Write the host env file. Secrets go via --env-file, never via `docker run -e`
#    (so they do not appear in the process list). Permissions 600.
echo "==> Writing ${ENV_FILE}"
mkdir -p "${ENV_DIR}"
umask 177
cat > "${ENV_FILE}" <<EOF
RAILS_MASTER_KEY=${RAILS_MASTER_KEY}
TLS_DOMAIN=${TLS_DOMAIN}
IMAGE=${IMAGE}
EOF
umask 022
chmod 600 "${ENV_FILE}"

# 4. Create the named volume for persistent /rails/storage data (idempotent).
echo "==> Ensuring volume ${VOLUME}"
docker volume create "${VOLUME}" >/dev/null

# 5. Pull the image.
echo "==> Pulling ${IMAGE}"
docker pull "${IMAGE}"

# 6. Replace any existing container and (re)start.
if docker ps -a --format '{{.Names}}' | grep -qx "${CONTAINER}"; then
  echo "==> Removing existing container ${CONTAINER}"
  docker stop "${CONTAINER}" >/dev/null 2>&1 || true
  docker rm "${CONTAINER}" >/dev/null 2>&1 || true
fi

echo "==> Starting container ${CONTAINER}"
docker run -d \
  --name "${CONTAINER}" \
  --restart "${RESTART_POLICY}" \
  -p "${HTTP_PORT}" \
  -p "${HTTPS_PORT}" \
  -v "${VOLUME}:${MOUNT}" \
  --env-file "${ENV_FILE}" \
  "${IMAGE}"

# 7. Done.
echo "==> Beams is starting."
echo "    Health check (HTTP): curl -fsS http://localhost/up"
if [ -n "${TLS_DOMAIN}" ]; then
  echo "    Health check (HTTPS): curl -fsS https://${TLS_DOMAIN}/up"
fi
echo "    Logs: docker logs -f ${CONTAINER}"
