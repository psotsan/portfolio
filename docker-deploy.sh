#!/usr/bin/env bash
# =============================================================================
# docker-deploy.sh
#
# Run on everey release / deploy.
# =============================================================================
set -euo pipefail

# --------------- defaults ---------------
DEFAULT_CONTAINER_NAME="portfolio"
DEFAULT_WAIT_MAX_ATTEMPTS=10
DEFAULT_WAIT_DELAY=2
DEFAULT_IMAGE_TAG="ghcr.io/psotsan/portfolio:latest"
DEFAULT_HOST_PORT=8000
DEFAULT_ENV_FILE="$HOME/.env"

CONTAINER_NAME="$DEFAULT_CONTAINER_NAME"
WAIT_MAX_ATTEMPTS="$DEFAULT_WAIT_MAX_ATTEMPTS"
WAIT_DELAY="$DEFAULT_WAIT_DELAY"
IMAGE_TAG="$DEFAULT_IMAGE_TAG"
HOST_PORT="$DEFAULT_HOST_PORT"
ENV_FILE="$DEFAULT_ENV_FILE"
SKIP_MIGRATIONS=false
SKIP_COLLECTSTATIC=false

# --------------- usage ---------------
usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --container-name NAME    Container name (default: $DEFAULT_CONTAINER_NAME)
  --wait-max-attempts N    Max attempts waiting (default: $DEFAULT_WAIT_MAX_ATTEMPTS)
  --wait-delay SEC         Seconds between attempts (default: $DEFAULT_WAIT_DELAY)
  --tag TAG                Docker image tag (default: $DEFAULT_IMAGE_TAG)
  --port PORT              Host port mapping (default: $DEFAULT_HOST_PORT)
  --env-file PATH          Path to .env file (default: $DEFAULT_ENV_FILE)
  --skip-migrations        Skip Django migrations
  --skip-collectstatic     Skip Django collectstatic
  -h, --help               Show this help and exit
EOF
  exit 0
}

# --------------- parse args ---------------
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --container-name)    CONTAINER_NAME="$2";    shift 2 ;;
      --wait-max-attempts) WAIT_MAX_ATTEMPTS="$2"; shift 2 ;;
      --wait-delay)        WAIT_DELAY="$2";        shift 2 ;;
      --tag)               IMAGE_TAG="$2";          shift 2 ;;
      --port)              HOST_PORT="$2";          shift 2 ;;
      --env-file)          ENV_FILE="$2";           shift 2 ;;
      --skip-migrations)   SKIP_MIGRATIONS=true;   shift   ;;
      --skip-collectstatic)SKIP_COLLECTSTATIC=true;shift   ;;
      -h|--help)           usage                            ;;
      *) echo "[ERROR] Unknown option: $1"; usage           ;;
    esac
  done
}

# --------------- error handling ---------------
handle_error() {
  local exit_code=$?
  local line_no=$1
  echo "[ERROR] docker-deploy.sh - line ${line_no}:"
  echo "       command ended with code ${exit_code}"
  exit "${exit_code}"
}
trap 'handle_error $LINENO' ERR

# --------------- preflight ---------------
preflight() {
  if [ ! -f "$ENV_FILE" ]; then
    echo "[ERROR] ${ENV_FILE} not found."
    echo "       Run docker-setup-env.sh first to generate it."
    exit 1
  fi

  if ! command -v docker &> /dev/null; then
    echo "[ERROR] docker not found."
    echo "       Run docker-bootstrap-vps.sh first to install it."
    exit 1
  fi
}

# --------------- wait for container ---------------
wait_for_container() {
  local name="$1"

  echo "[..] Waiting for container '${name}' to be ready..."
  for i in $(seq 1 "${WAIT_MAX_ATTEMPTS}"); do
    if docker exec "${name}" python -c \
         "import django; django.setup(); print('ok')" 2>/dev/null; then
      echo "[OK] Container '${name}' ready."
      return 0
    fi
    if [ "$i" -eq "${WAIT_MAX_ATTEMPTS}" ]; then
      echo "[ERROR] Container '${name}' not ready after" \
           "${WAIT_MAX_ATTEMPTS} attempts."
      docker logs "${name}" --tail 20
      return 1
    fi
    sleep "${WAIT_DELAY}"
  done
}

# --------------- docker deployment ---------------
deploy_docker() {
  echo "[..] Pulling image ${IMAGE_TAG}..."
  docker pull "$IMAGE_TAG"

  echo "[..] Stopping existing container '${CONTAINER_NAME}'..."
  docker stop "$CONTAINER_NAME" 2>/dev/null || true
  docker rm "$CONTAINER_NAME" 2>/dev/null || true

  echo "[..] Starting new container '${CONTAINER_NAME}'..."
  docker run -d \
    --name "$CONTAINER_NAME" \
    -p "${HOST_PORT}:8000" \
    --restart unless-stopped \
    --env-file "$ENV_FILE" \
    "$IMAGE_TAG"

  echo "[OK] Container started."
  wait_for_container "$CONTAINER_NAME"
}

# --------------- django management commands ---------------
django_migrate() {
  echo "[..] Running migrations..."
  docker exec "$CONTAINER_NAME" python manage.py migrate --noinput
}

django_createsuperuser() {
  echo "[..] Creating superuser..."
  docker exec \
    --env-file "$ENV_FILE" \
    "$CONTAINER_NAME" python manage.py createsuperuser --noinput \
    || echo "[WARN] Superuser already exists (or creation failed)"
}

django_collectstatic() {
  echo "[..] Collecting static files..."
  docker exec "$CONTAINER_NAME" python manage.py collectstatic --noinput
}

# --------------- smoke test ---------------
smoke_test() {
  echo "[..] Running smoke test..."
  curl -I "http://localhost:${HOST_PORT}"
  echo "[OK] Smoke test completed."
}

# ------------------ main ------------------
main() {
  parse_args "$@"

  echo "============================================="
  echo " docker-deploy.sh"
  echo " Deploy Django app with Docker"
  echo "============================================="

  preflight
  deploy_docker

  if [ "$SKIP_MIGRATIONS" = false ]; then
    django_migrate
  fi

  django_createsuperuser

  if [ "$SKIP_COLLECTSTATIC" = false ]; then
    django_collectstatic
  fi

  smoke_test

  echo ""
  echo "============================================="
  echo " Deploy complete!"
  echo "============================================="
}

main "$@"
