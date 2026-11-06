#!/usr/bin/env bash
# One-command install: checks Docker and the image, creates .env, builds and starts, waits for healthy.
# Usage: ./install.sh [path-to-the-tar-file-from-the-portal]   (or set IRIS_IMAGE_TAR; not needed when the image is already loaded)
set -u
URL="http://localhost:52773/agenticprod/dashboard.html"
TAR="${1:-${IRIS_IMAGE_TAR:-}}"

die() { echo "ERROR: $*" >&2; exit 1; }

cd "$(dirname "$0")" || die "cannot enter the repo folder"

# Image name: environment first, then .env, then the tested build
IMAGE="${IRIS_IMAGE:-}"
if [ -z "$IMAGE" ] && [ -f .env ]; then
  IMAGE="$(sed -n 's/^IRIS_IMAGE=//p' .env | tail -n 1 | tr -d '"')"
fi
IMAGE="${IMAGE:-irishealth-community:2027.1.0AI.109.0}"
export IRIS_IMAGE="$IMAGE"

# 1. Docker and compose
command -v docker >/dev/null 2>&1 || die "docker is not installed or not on PATH"
docker info >/dev/null 2>&1 || die "docker is installed but the daemon is not running"
docker compose version >/dev/null 2>&1 || die "'docker compose' (v2) is not available"

# 2. The AI Hub image is not public. It comes as a tar file from the AI Hub early-access portal;
# docker load prints its internal name, and the app builds FROM the short tag. Take the tar path,
# an image that is already loaded under the internal name, or one already tagged.
INTERNAL="docker.iscinternal.com/docker-intersystems/intersystems/irishealth-community:2027.1.0AI.109.0"
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  if [ -n "$TAR" ]; then
    [ -f "$TAR" ] || die "image file not found: $TAR"
    echo "Loading $TAR (this takes a minute)..."
    out="$(docker load -i "$TAR")" || die "docker load failed"
    echo "$out"
    loaded="$(printf '%s\n' "$out" | sed -n 's/^Loaded image: //p' | tail -n 1)"
    [ -n "$loaded" ] || die "docker load did not print a 'Loaded image:' name"
    echo "Running: docker tag $loaded $IMAGE"
    docker tag "$loaded" "$IMAGE" || die "docker tag failed for $loaded"
  elif docker image inspect "$INTERNAL" >/dev/null 2>&1; then
    echo "Found the loaded image $INTERNAL"
    echo "Running: docker tag $INTERNAL $IMAGE"
    docker tag "$INTERNAL" "$IMAGE" || die "docker tag failed for $INTERNAL"
  fi
fi
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  cat >&2 <<MSG
ERROR: the image $IMAGE is missing.

This app needs $IMAGE (InterSystems IRIS for Health with AI Hub, early access
build 109, built on build 154). The plain iris-community image of the same build does not work: it has no
EnsLib.HL7 classes, and setup stops with a message saying so. The image is not public: download the
tar file from the AI Hub early-access portal, then load it and tag it:

  docker load -i <the tar file from the portal>
  docker tag docker.iscinternal.com/docker-intersystems/intersystems/irishealth-community:2027.1.0AI.109.0 $IMAGE

docker load prints that internal name. Or run: ./install.sh path/to/the-tar-file-from-the-portal
Never push this image, or an image built from it, to a public registry.
MSG
  exit 1
fi

# 3. .env: created once, never overwritten, never printed
if [ ! -f .env ]; then
  [ -f .env.example ] || die ".env.example is missing"
  cp .env.example .env || die "could not create .env"
  echo "Created .env from .env.example"
fi
if ! grep -Eq '^OPENAI_API_KEY=.+' .env; then
  echo "OPENAI_API_KEY is empty in .env: replay mode works without a key. Add one for live mode."
fi

# 4. Build and start
echo "Building and starting (first build takes about 6 minutes)..."
docker compose up -d --build || die "docker compose up failed"

# 5. Wait for the healthcheck: up to 20 minutes, one dot every 15 seconds
cid="$(docker compose ps -q iris)"
[ -n "$cid" ] || die "the iris container was not created"
printf 'Waiting for IRIS to be healthy (setup runs on first start)'
healthy=0
for _ in $(seq 1 80); do
  state="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$cid" 2>/dev/null)"
  if [ "$state" = "healthy" ]; then healthy=1; break; fi
  printf '.'
  sleep 15
done
echo
if [ "$healthy" -ne 1 ]; then
  echo "ERROR: IRIS was not healthy after 20 minutes. Last 20 log lines:" >&2
  docker compose logs --tail 20 iris >&2
  exit 1
fi

cat <<MSG

Ready.
  Dashboard:  $URL
  Logins:     SuperUser / SYS (demo admin)
              reviewer / Review-Demo-2026 (read-only)

Replay the recorded evaluation (no key, no cost), in the IRISAPP terminal:
  docker compose exec iris iris session iris -U IRISAPP
  do ##class(AgenticProd.Eval.Runner).Run("gpt-4o-mini", "replay demo", "all", "replay")
MSG
