#!/bin/sh
set -eu

BASE_DOMAIN="${BASE_DOMAIN:-wifi-code.example.com}"
CONTAINER_NAME="${CONTAINER_NAME:-wifi-code-server}"
IMAGE_NAME="${IMAGE_NAME:-wifi-code-server:latest}"
HTTP_PORT="${HTTP_PORT:-8080}"
DNS_PORT="${DNS_PORT:-53}"
ALLOW_DOCKER_INSTALL="${ALLOW_DOCKER_INSTALL:-1}"
STOP_KNOWN_CONFLICTS="${STOP_KNOWN_CONFLICTS:-0}"
IMAGE_TAR="${IMAGE_TAR:-wifi-code-server-amd64.tar}"

log() {
  printf '[wifi-code-server] %s\n' "$*"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

install_docker_if_needed() {
  if need_cmd docker; then
    return
  fi
  if [ "$ALLOW_DOCKER_INSTALL" != "1" ]; then
    log "Docker is not installed and automatic installation is disabled."
    exit 1
  fi
  log "Docker not found. Installing Docker with the system package manager."
  if need_cmd apt-get; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg lsb-release docker.io
    systemctl enable --now docker >/dev/null 2>&1 || service docker start >/dev/null 2>&1 || true
  elif need_cmd yum; then
    yum install -y docker
    systemctl enable --now docker >/dev/null 2>&1 || service docker start >/dev/null 2>&1 || true
  elif need_cmd dnf; then
    dnf install -y docker
    systemctl enable --now docker >/dev/null 2>&1 || service docker start >/dev/null 2>&1 || true
  else
    log "No supported package manager found. Please install Docker manually."
    exit 1
  fi
}

stop_known_conflicts_if_allowed() {
  if [ "$STOP_KNOWN_CONFLICTS" != "1" ]; then
    return
  fi
  for name in shadow-radio; do
    if docker ps --format '{{.Names}}' | grep -qx "$name"; then
      log "Stopping known conflicting container: $name"
      docker stop "$name" >/dev/null
    fi
  done
}

ensure_ports_available() {
  busy=""
  if need_cmd ss; then
    if ss -ltnup | grep -q ":$HTTP_PORT "; then
      busy="$busy tcp/$HTTP_PORT"
    fi
    if ss -lunp | grep -q ":$DNS_PORT "; then
      busy="$busy udp/$DNS_PORT"
    fi
    if ss -ltnp | grep -q ":$DNS_PORT "; then
      busy="$busy tcp/$DNS_PORT"
    fi
  elif need_cmd netstat; then
    if netstat -lntup 2>/dev/null | grep -q ":$HTTP_PORT "; then
      busy="$busy tcp/$HTTP_PORT"
    fi
    if netstat -lnup 2>/dev/null | grep -q ":$DNS_PORT "; then
      busy="$busy udp/$DNS_PORT"
    fi
    if netstat -lntp 2>/dev/null | grep -q ":$DNS_PORT "; then
      busy="$busy tcp/$DNS_PORT"
    fi
  fi
  if [ -n "$busy" ]; then
    log "Port(s) already in use:$busy"
    log "Stop the conflicting service, or enable the known-conflict switch if it is the old test container."
    exit 1
  fi
}

log "Base domain: $BASE_DOMAIN"
log "Image tar: $IMAGE_TAR"
install_docker_if_needed

if ! [ -f "$IMAGE_TAR" ]; then
  log "Image tar not found: $IMAGE_TAR"
  exit 1
fi

docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
stop_known_conflicts_if_allowed
ensure_ports_available

log "Loading Docker image."
docker load -i "$IMAGE_TAR"

log "Starting container: $CONTAINER_NAME"
docker run -d \
  --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  -p "$DNS_PORT:53/udp" \
  -p "$DNS_PORT:53/tcp" \
  -p "$HTTP_PORT:8080/tcp" \
  -e BASE_DOMAIN="$BASE_DOMAIN" \
  "$IMAGE_NAME"

sleep 1
log "Container status:"
docker ps --filter "name=$CONTAINER_NAME" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

log "HTTP health:"
curl -fsS "http://127.0.0.1:$HTTP_PORT/health" || true
printf '\n'

if need_cmd dig; then
  log "DNS health:"
  dig "@127.0.0.1" +short "health.$BASE_DOMAIN" A || true
else
  log "dig not found; skipped local DNS query check."
fi

log "Done."
