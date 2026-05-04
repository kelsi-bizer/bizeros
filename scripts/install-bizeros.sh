#!/usr/bin/env bash
# BizerOS install script — provisions a fresh Linux VM to run BizerOS, or
# updates an existing install in place.
#
# Fresh install:
#   curl -fsSL https://raw.githubusercontent.com/kelsi-bizer/bizeros/develop/scripts/install-bizeros.sh \
#     | sudo bash -s -- --domain client1.bizeros.com
#
# Update an existing install (preserves .env, secrets, app data, certs):
#   curl -fsSL .../install-bizeros.sh | sudo bash -s -- --update
#
# Or download and run interactively:
#   curl -fsSL .../install-bizeros.sh -o install-bizeros.sh
#   sudo bash install-bizeros.sh --domain client1.bizeros.com
#
# Flags:
#   --domain <fqdn>       (required for fresh install) Public domain for the
#                         dashboard. On --update, taken from the existing .env.
#   --update              Update an existing install in place: skip DNS preflight
#                         and Traefik state wipe, pull the latest image, recreate
#                         containers, verify the existing cert is still valid.
#                         Requires .env to already exist at --install-dir.
#   --acme-email <email>  (default: admin@<domain>) Let's Encrypt contact email
#   --cf-api-token <tok>  (optional) Cloudflare API token with DNS-edit scope on
#                         <domain>. If provided, Traefik issues a single
#                         *.<domain> wildcard cert via DNS-01 covering every
#                         exposed app. Without it, each exposed app gets its own
#                         per-subdomain HTTP-01 cert (subject to Let's Encrypt's
#                         50-cert/week per registered-domain limit).
#   --sentry-dsn <dsn>    (optional) Enable backend error reporting to Sentry.
#                         Writes SENTRY_DSN to .env and sets
#                         ALLOW_ERROR_MONITORING=true. Operators can also
#                         toggle this later from Settings.
#   --version <tag>       (default: nightly) Image tag to pull
#   --branch <branch>     (default: develop) Branch to fetch the compose file from
#   --install-dir <dir>   (default: /opt/bizeros) Where to install
#   --local-domain <d>    (default: bizeros.local) LAN domain for Traefik
#   --skip-dns-check      Skip the public-DNS preflight (use only if your DNS
#                         propagates slowly and you've manually verified it)

set -o errexit
set -o nounset
set -o pipefail

# ---------- defaults ----------
DOMAIN=""
ACME_EMAIL=""
CF_API_TOKEN=""
SENTRY_DSN=""
VERSION="nightly"
BRANCH="develop"
INSTALL_DIR="/opt/bizeros"
LOCAL_DOMAIN="bizeros.local"
SKIP_DNS_CHECK=0
UPDATE_MODE=0
COMPOSE_URL_BASE="https://raw.githubusercontent.com/kelsi-bizer/bizeros"

# ---------- arg parsing ----------
while [ $# -gt 0 ]; do
  case "$1" in
    --domain)        shift; DOMAIN="$1" ;;
    --acme-email)    shift; ACME_EMAIL="$1" ;;
    --cf-api-token)  shift; CF_API_TOKEN="$1" ;;
    --sentry-dsn)    shift; SENTRY_DSN="$1" ;;
    --version)       shift; VERSION="$1" ;;
    --branch)        shift; BRANCH="$1" ;;
    --install-dir)   shift; INSTALL_DIR="$1" ;;
    --local-domain)  shift; LOCAL_DOMAIN="$1" ;;
    --skip-dns-check) SKIP_DNS_CHECK=1 ;;
    --update)         UPDATE_MODE=1 ;;
    -h|--help)
      sed -n '2,38p' "$0"
      exit 0 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
  shift
done

# In --update mode, take DOMAIN from the existing .env if not supplied. This
# lets the operator update with a single command:
#    curl -fsSL .../install-bizeros.sh | sudo bash -s -- --update
if [ "$UPDATE_MODE" -eq 1 ]; then
  if [ ! -f "$INSTALL_DIR/.env" ]; then
    echo "ERROR: --update requires an existing .env at $INSTALL_DIR/.env" >&2
    echo "       (no install detected; drop --update for a fresh install)" >&2
    exit 1
  fi
  if [ -z "$DOMAIN" ]; then
    DOMAIN="$(grep -E '^DOMAIN=' "$INSTALL_DIR/.env" | head -1 | cut -d= -f2-)"
    if [ -z "$DOMAIN" ]; then
      echo "ERROR: existing .env does not contain DOMAIN" >&2
      exit 1
    fi
  fi
fi

if [ -z "$DOMAIN" ]; then
  echo "ERROR: --domain is required (e.g. --domain client1.bizeros.com)" >&2
  exit 1
fi

if [ -z "$ACME_EMAIL" ]; then
  ACME_EMAIL="admin@$DOMAIN"
fi

# ---------- preflight ----------
if [ "$UPDATE_MODE" -eq 1 ]; then
  echo "==> BizerOS updater (in-place; preserving .env, secrets, app data, certs)"
else
  echo "==> BizerOS installer"
fi
echo "    domain        = $DOMAIN"
echo "    acme email    = $ACME_EMAIL"
echo "    local domain  = $LOCAL_DOMAIN"
echo "    image tag     = $VERSION"
echo "    install dir   = $INSTALL_DIR"
echo "    compose source= $BRANCH"
if [ -n "$CF_API_TOKEN" ]; then
  echo "    cert mode     = wildcard (Cloudflare DNS-01)"
else
  echo "    cert mode     = per-app (HTTP-01)"
fi
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

# Ensure dig is available for the DNS preflight (skipped in --update mode).
if [ "$UPDATE_MODE" -eq 0 ] && ! command -v dig >/dev/null 2>&1; then
  echo "==> installing dnsutils for DNS preflight"
  apt-get update -qq && apt-get install -y -qq dnsutils >/dev/null
fi

# ---------- detect public IP ----------
# Skipped in --update mode (existing install already proved DNS reaches this VM).
if [ "$UPDATE_MODE" -eq 0 ]; then
  PUBLIC_IP="$(curl -fsS --max-time 10 https://api.ipify.org 2>/dev/null || true)"
  if [ -z "$PUBLIC_IP" ]; then
    echo "ERROR: could not detect this VM's public IP (api.ipify.org unreachable)" >&2
    exit 1
  fi
  echo "==> VM public IP: $PUBLIC_IP"
fi

# ---------- DNS preflight ----------
# Skipped in --update mode (existing install already proved DNS works; re-running
# the preflight just delays the update by 5+ seconds for no benefit).
if [ "$UPDATE_MODE" -eq 0 ] && [ "$SKIP_DNS_CHECK" -eq 0 ]; then
  echo "==> checking public DNS for $DOMAIN"
  RESOLVED="$(dig +short +time=5 +tries=2 @1.1.1.1 "$DOMAIN" A 2>/dev/null | tail -1)"
  if [ -z "$RESOLVED" ]; then
    echo "ERROR: $DOMAIN does not resolve via public DNS (1.1.1.1)." >&2
    echo "       Add an A record at your registrar:" >&2
    echo "         $DOMAIN              A    $PUBLIC_IP" >&2
    echo "         *.$DOMAIN            A    $PUBLIC_IP" >&2
    echo "       Then retry. Re-run with --skip-dns-check if propagation is slow." >&2
    exit 1
  fi
  if [ "$RESOLVED" != "$PUBLIC_IP" ]; then
    echo "ERROR: $DOMAIN resolves to $RESOLVED but this VM's public IP is $PUBLIC_IP." >&2
    echo "       Update the A record at your registrar to point at $PUBLIC_IP and retry." >&2
    exit 1
  fi
  echo "    $DOMAIN → $RESOLVED ✓"

  WILDCARD_PROBE="bizeros-install-probe.$DOMAIN"
  WILDCARD_RESOLVED="$(dig +short +time=5 +tries=2 @1.1.1.1 "$WILDCARD_PROBE" A 2>/dev/null | tail -1)"
  if [ "$WILDCARD_RESOLVED" != "$PUBLIC_IP" ]; then
    echo "WARN: wildcard *.$DOMAIN does not resolve to $PUBLIC_IP (probe got '${WILDCARD_RESOLVED:-NXDOMAIN}')." >&2
    echo "      Apps installed with auto-routing land at <app>.$DOMAIN — they will 404 until you add" >&2
    echo "      a wildcard A record (*.$DOMAIN → $PUBLIC_IP) at your registrar. Continuing anyway." >&2
  else
    echo "    *.$DOMAIN → $PUBLIC_IP ✓"
  fi
fi

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
ACME_EMAIL=$ACME_EMAIL
MAX_BACKUPS=7

POSTGRES_PASSWORD=$POSTGRES_PASSWORD
RABBITMQ_USERNAME=tipi
RABBITMQ_PASSWORD=$RABBITMQ_PASSWORD
JWT_SECRET=$JWT_SECRET

APPS_REPO_URL=https://github.com/kelsi-bizer/bizeros-appstore
APPS_REPO_ID=bizeros
EOF
  chmod 600 .env
else
  echo "==> reusing existing .env"
  # Sync DOMAIN, ACME_EMAIL, TIPI_VERSION to the flags. Replace if present, append if not.
  # MAX_BACKUPS is only added if missing (existing operator overrides preserved).
  for kv in "DOMAIN=$DOMAIN" "ACME_EMAIL=$ACME_EMAIL" "TIPI_VERSION=$VERSION"; do
    key="${kv%%=*}"
    if grep -q "^${key}=" .env; then
      sed -i "s|^${key}=.*|${kv}|" .env
    else
      echo "$kv" >> .env
    fi
  done
  # Backfill MAX_BACKUPS=7 only if the existing .env is missing the key. This
  # preserves any value the operator set explicitly (e.g. MAX_BACKUPS=14 for
  # longer retention, or =0 to keep all backups indefinitely).
  if ! grep -q "^MAX_BACKUPS=" .env; then
    echo "MAX_BACKUPS=7" >> .env
  fi
fi

# ---------- DNS-01 wildcard cert (optional, Cloudflare) ----------
# Without these env vars Traefik issues per-app HTTP-01 certs (works out of the
# box but hits LE rate limits faster). With them, Traefik issues a single
# *.<DOMAIN> cert via DNS-01 covering every exposed app. The compose generator
# in runtipi auto-detects DNS_CHALLENGE_PROVIDER and routes auto-routed apps to
# the wildcard resolver only when it's set.
sync_env_var() {
  local key="$1"
  local value="$2"
  if grep -q "^${key}=" .env; then
    if [ -n "$value" ]; then
      sed -i "s|^${key}=.*|${key}=${value}|" .env
    else
      sed -i "/^${key}=/d" .env
    fi
  elif [ -n "$value" ]; then
    echo "${key}=${value}" >> .env
  fi
}

if [ -n "$CF_API_TOKEN" ]; then
  echo "==> enabling Cloudflare DNS-01 wildcard cert"
  sync_env_var "DNS_CHALLENGE_PROVIDER" "cloudflare"
  sync_env_var "CLOUDFLARE_DNS_API_TOKEN" "$CF_API_TOKEN"
fi
# A previously-set DNS provider in .env stays sticky on re-run unless the
# operator removes those lines manually. That's intentional — re-running the
# installer for an update shouldn't silently disable wildcard certs.

# ---------- Sentry error reporting (optional, opt-in) ----------
# Same sticky-on-re-run semantics as Cloudflare: passing --sentry-dsn writes
# the DSN and enables ALLOW_ERROR_MONITORING. Existing values stay until the
# operator removes them manually.
if [ -n "$SENTRY_DSN" ]; then
  echo "==> enabling Sentry error reporting"
  sync_env_var "SENTRY_DSN" "$SENTRY_DSN"
  sync_env_var "ALLOW_ERROR_MONITORING" "true"
fi

# ---------- clean stale Traefik state ----------
# acme.json caches a Let's Encrypt account+cert tied to the previous DOMAIN/email.
# Stale state from a failed prior install causes "served self-signed *.bizeros.local"
# even after the underlying problem is fixed. We always re-render traefik.yml so
# any template changes in the new image are picked up. We only blow away acme.json
# on a fresh install -- in update mode the cert is already valid and re-issuing
# burns Let's Encrypt rate limit for no reason.
if [ "$UPDATE_MODE" -eq 1 ]; then
  echo "==> re-rendering Traefik config (preserving acme.json)"
else
  echo "==> clearing stale Traefik state"
  rm -f .internal/traefik/shared/acme.json .internal/traefik/shared/acme-wildcard.json
fi
rm -f .internal/traefik/traefik.yml

# ---------- pull + start ----------
echo "==> pulling image ghcr.io/kelsi-bizer/bizeros:$VERSION"
docker compose -f docker-compose.bizeros.yml pull

# Surface what we actually got. OCI revision label is set by the GHCR build
# pipeline (metadata-action). If the publish workflow hasn't caught up yet,
# this will print a commit SHA older than develop's HEAD — useful diagnostic.
IMAGE_REVISION="$(docker inspect "ghcr.io/kelsi-bizer/bizeros:$VERSION" \
  --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' 2>/dev/null || true)"
IMAGE_CREATED="$(docker inspect "ghcr.io/kelsi-bizer/bizeros:$VERSION" \
  --format '{{.Created}}' 2>/dev/null || true)"
echo "    image revision: ${IMAGE_REVISION:-unknown} (built ${IMAGE_CREATED:-unknown})"

echo "==> starting BizerOS"
docker compose -f docker-compose.bizeros.yml up -d

# ---------- wait for dashboard ----------
echo
echo "==> waiting for dashboard health"
DASH_READY=0
for _ in $(seq 1 60); do
  if docker exec runtipi curl -fsS http://localhost:3000/api/health >/dev/null 2>&1; then
    DASH_READY=1
    break
  fi
  sleep 5
done

if [ "$DASH_READY" -eq 0 ]; then
  echo "WARN: dashboard didn't become healthy in 5 minutes." >&2
  echo "      Logs: cd $INSTALL_DIR && docker compose -f docker-compose.bizeros.yml logs runtipi" >&2
  exit 1
fi

# ---------- wait for Let's Encrypt cert ----------
echo "==> waiting for Let's Encrypt cert (this can take up to 90s)"
CERT_READY=0
for _ in $(seq 1 18); do
  CERT_SUBJECT="$(echo | openssl s_client -connect "$DOMAIN:443" -servername "dash.$DOMAIN" 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null || true)"
  if echo "$CERT_SUBJECT" | grep -qE "(dash\.)?$DOMAIN"; then
    CERT_READY=1
    break
  fi
  sleep 5
done

echo
if [ "$UPDATE_MODE" -eq 1 ]; then
  HEADLINE_OK="BizerOS updated."
  HEADLINE_PARTIAL="BizerOS updated, but the cert check failed. Verify manually."
else
  HEADLINE_OK="BizerOS is up."
  HEADLINE_PARTIAL="BizerOS is up, but Traefik hasn't issued a Let's Encrypt cert yet."
fi

if [ "$CERT_READY" -eq 1 ]; then
  echo "$HEADLINE_OK"
  echo "  Dashboard:  https://dash.$DOMAIN"
  echo "  Local:      https://$LOCAL_DOMAIN  (point /etc/hosts at $INTERNAL_IP)"
else
  echo "$HEADLINE_PARTIAL"
  echo "  Dashboard:  https://dash.$DOMAIN  (will load once the cert issues)"
  echo "  Tail certs: cd $INSTALL_DIR && docker compose -f docker-compose.bizeros.yml \\"
  echo "              logs -f runtipi-reverse-proxy 2>&1 | grep -iE 'acme|certificate'"
fi
echo "  Logs:       cd $INSTALL_DIR && docker compose -f docker-compose.bizeros.yml logs -f runtipi"
echo "  Stop:       cd $INSTALL_DIR && docker compose -f docker-compose.bizeros.yml down"
echo "  Update:     curl -fsSL $COMPOSE_URL_BASE/$BRANCH/scripts/install-bizeros.sh | sudo bash -s -- --update"
exit 0
