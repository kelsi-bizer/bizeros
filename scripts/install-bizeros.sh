#!/usr/bin/env bash
# BizerOS install script — provisions a fresh Linux VM to run BizerOS.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/kelsi-bizer/bizeros/main/scripts/install-bizeros.sh \
#     | bash -s -- --domain client1.bizeros.com
#
# Or download and run interactively:
#   curl -fsSL .../install-bizeros.sh -o install-bizeros.sh
#   sudo bash install-bizeros.sh --domain client1.bizeros.com
#
# Flags:
#   --domain <fqdn>     (required) Public domain for the dashboard
#   --version <tag>     (default: nightly) Image tag to pull
#   --branch <branch>   (default: develop) Branch to fetch the compose file from
#   --install-dir <dir> (default: /opt/bizeros) Where to install
#   --local-domain <d>  (default: bizeros.local) LAN domain for Traefik

set -o errexit
set -o nounset
set -o pipefail

# ---------- defaults ----------
DOMAIN=""
VERSION="nightly"
BRANCH="develop"
INSTALL_DIR="/opt/bizeros"
LOCAL_DOMAIN="bizeros.local"
COMPOSE_URL_BASE="https://raw.githubusercontent.com/kelsi-bizer/bizeros"

# ---------- arg parsing ----------
while [ $# -gt 0 ]; do
  case "$1" in
    --domain)        shift; DOMAIN="$1" ;;
    --version)       shift; VERSION="$1" ;;
    --branch)        shift; BRANCH="$1" ;;
    --install-dir)   shift; INSTALL_DIR="$1" ;;
    --local-domain)  shift; LOCAL_DOMAIN="$1" ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
  shift
done

if [ -z "$DOMAIN" ]; then
  echo "ERROR: --domain is required (e.g. --domain client1.bizeros.com)" >&2
  exit 1
fi

# ---------- preflight ----------
echo "==> BizerOS installer"
echo "    domain        = $DOMAIN"
echo "    local domain  = $LOCAL_DOMAIN"
echo "    image tag     = $VERSION"
echo "    install dir   = $INSTALL_DIR"
echo "    compose source= $BRANCH"
echo

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|aarch64|arm64) ;;
  *) echo "ERROR: unsupported architecture $ARCH (need x86_64 or arm64)" >&2; exit 1 ;;
esac

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: run as root (sudo bash install-bizeros.sh ...)" >&2
  exit 1
fi

OS_ID="$(. /etc/os-release && echo "$ID")"
case "$OS_ID" in
  ubuntu|debian) ;;
  *) echo "WARN: tested on Ubuntu/Debian, $OS_ID may need manual Docker install" ;;
esac

# ---------- docker ----------
if ! command -v docker >/dev/null 2>&1; then
  echo "==> installing Docker"
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
else
  echo "==> Docker already installed ($(docker -v))"
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: Docker installed but 'docker compose' plugin missing" >&2
  exit 1
fi

# ---------- workdir ----------
echo "==> preparing $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# ---------- compose file ----------
COMPOSE_URL="$COMPOSE_URL_BASE/$BRANCH/docker-compose.bizeros.yml"
echo "==> fetching $COMPOSE_URL"
if ! curl -fsSL "$COMPOSE_URL" -o docker-compose.bizeros.yml; then
  echo "ERROR: could not download compose file from $COMPOSE_URL" >&2
  echo "       (check that --branch=$BRANCH exists on kelsi-bizer/bizeros)" >&2
  exit 1
fi

# ---------- secrets + env ----------
gen_secret() { openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | xxd -p -c 64; }

INTERNAL_IP="$(hostname -I | awk '{print $1}')"
if [ -z "$INTERNAL_IP" ]; then
  echo "ERROR: could not detect internal IP" >&2
  exit 1
fi

if [ ! -f .env ]; then
  echo "==> generating .env with random secrets"
  POSTGRES_PASSWORD="$(gen_secret)"
  RABBITMQ_PASSWORD="$(gen_secret)"
  JWT_SECRET="$(gen_secret)"

  cat >.env <<EOF
DOMAIN=$DOMAIN
LOCAL_DOMAIN=$LOCAL_DOMAIN
INTERNAL_IP=$INTERNAL_IP
TIPI_VERSION=$VERSION
ROOT_FOLDER_HOST=$INSTALL_DIR/.internal
LOG_LEVEL=info
ACME_EMAIL=admin@$DOMAIN

POSTGRES_PASSWORD=$POSTGRES_PASSWORD
RABBITMQ_USERNAME=tipi
RABBITMQ_PASSWORD=$RABBITMQ_PASSWORD
JWT_SECRET=$JWT_SECRET

APPS_REPO_URL=https://github.com/kelsi-bizer/bizeros-appstore
APPS_REPO_ID=bizeros
EOF
  chmod 600 .env
else
  echo "==> reusing existing .env (delete it to regenerate)"
fi

# ---------- pull + start ----------
echo "==> pulling image ghcr.io/kelsi-bizer/bizeros:$VERSION"
docker compose -f docker-compose.bizeros.yml pull

echo "==> starting BizerOS"
docker compose -f docker-compose.bizeros.yml up -d

echo
echo "==> waiting for dashboard health"
for i in $(seq 1 60); do
  if docker exec runtipi curl -fsS http://localhost:3000/api/health >/dev/null 2>&1; then
    echo
    echo "BizerOS is up."
    echo "  Dashboard:  https://$DOMAIN"
    echo "  Local:      https://$LOCAL_DOMAIN  (point /etc/hosts at $INTERNAL_IP)"
    echo "  Logs:       cd $INSTALL_DIR && docker compose -f docker-compose.bizeros.yml logs -f runtipi"
    echo "  Stop:       cd $INSTALL_DIR && docker compose -f docker-compose.bizeros.yml down"
    exit 0
  fi
  sleep 5
done

echo
echo "WARN: dashboard didn't become healthy in 5 minutes." >&2
echo "      Check logs: cd $INSTALL_DIR && docker compose -f docker-compose.bizeros.yml logs runtipi" >&2
exit 1
