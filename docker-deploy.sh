#!/usr/bin/env bash

set -euo pipefail

# --------------- defaults ---------------
DEFAULT_CONTAINER_NAME="portfolio"
DEFAULT_WAIT_MAX_ATTEMPTS=10
DEFAULT_WAIT_DELAY=2
DEFAULT_IMAGE_TAG="ghcr.io/psotsan/portfolio:latest"
DEFAULT_HOST_PORT=8000
DEFAULT_ENV_FILE="$HOME/.env"

# --------------- configurables ---------------
CONTAINER_NAME="$DEFAULT_CONTAINER_NAME"
WAIT_MAX_ATTEMPTS="$DEFAULT_WAIT_MAX_ATTEMPTS"
WAIT_DELAY="$DEFAULT_WAIT_DELAY"
IMAGE_TAG="$DEFAULT_IMAGE_TAG"
HOST_PORT="$DEFAULT_HOST_PORT"
ENV_FILE="$DEFAULT_ENV_FILE"
NO_SSL=false
NO_FIREWALL=false
SKIP_MIGRATIONS=false
SKIP_COLLECTSTATIC=false

# --------------- usage ---------------
usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --container-name NAME     Container name (default: $DEFAULT_CONTAINER_NAME)
  --wait-max-attempts N     Max attempts waiting for container (default: $DEFAULT_WAIT_MAX_ATTEMPTS)
  --wait-delay SEC          Seconds between attempts (default: $DEFAULT_WAIT_DELAY)
  --tag TAG                 Docker image tag (default: $DEFAULT_IMAGE_TAG)
  --port PORT               Host port mapping (default: $DEFAULT_HOST_PORT)
  --env-file PATH           Path to .env file (default: $DEFAULT_ENV_FILE)
  --no-ssl                  Skip SSL / certbot setup
  --no-firewall             Skip ufw configuration
  --skip-migrations         Skip Django migrations
  --skip-collectstatic      Skip Django collectstatic
  -h, --help                Show this help and exit
EOF
  exit 0
}

# --------------- parse args ---------------
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --container-name)       CONTAINER_NAME="$2";       shift 2 ;;
      --wait-max-attempts)    WAIT_MAX_ATTEMPTS="$2";    shift 2 ;;
      --wait-delay)           WAIT_DELAY="$2";           shift 2 ;;
      --tag)                  IMAGE_TAG="$2";            shift 2 ;;
      --port)                 HOST_PORT="$2";            shift 2 ;;
      --env-file)             ENV_FILE="$2";             shift 2 ;;
      --no-ssl)               NO_SSL=true;               shift   ;;
      --no-firewall)          NO_FIREWALL=true;          shift   ;;
      --skip-migrations)      SKIP_MIGRATIONS=true;      shift   ;;
      --skip-collectstatic)   SKIP_COLLECTSTATIC=true;   shift   ;;
      -h|--help)              usage                               ;;
      *) echo "[ERROR] Unknown option: $1"; usage                ;;
    esac
  done
}

# --------------- error handling ---------------
handle_error() {
  local exit_code=$?
  local line_no=$1
  echo "[ERROR] docker-deploy.sh - line ${line_no}: "
  echo "       command ended with code ${exit_code}"
  exit "${exit_code}"
}
trap 'handle_error $LINENO' ERR

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

# --------------- generate secret key ---------------
generate_secret_key() {
  python3 -c "
import secrets, string
chars = string.ascii_letters + string.digits + string.punctuation
print(''.join(secrets.choice(chars) for _ in range(50)))
"
}

# --------------- prompt & write .env ---------------
declare -a VAR_NAMES=(
  "DJANGO_ALLOWED_HOSTS"
  "PERSONAL_NAME"
  "PERSONAL_EMAIL"
  "PERSONAL_GITHUB"
  "PERSONAL_LINKEDIN"
  "AWS_STORAGE_BUCKET_NAME"
  "AWS_S3_REGION_NAME"
)

declare -a SUPERUSER_VARS=(
  "DJANGO_SUPERUSER_USERNAME"
  "DJANGO_SUPERUSER_EMAIL"
  "DJANGO_SUPERUSER_PASSWORD"
)

prompt_var() {
  local var="$1"
  local val
  while true; do
    read -r -p "  ${var}: " val
    [ -n "$val" ] && break
    echo "  [WARN] cannot be empty"
  done
  printf "%s" "$val"
}

format_var() {
  local var="$1"
  local val="$2"
  if [ "$var" = "DJANGO_ALLOWED_HOSTS" ]; then
    printf "%s=%s" "$var" "$val"
  else
    printf "%s='%s'" "$var" "$val"
  fi
}

write_env() {
  local var val
  local secret_key
  local env_content=""

  secret_key=$(generate_secret_key)
  env_content+="DJANGO_SECRET_KEY='${secret_key}'"$'\n'

  for var in "${VAR_NAMES[@]}"; do
    val=$(prompt_var "$var")
    env_content+="$(format_var "$var" "$val")"$'\n'
  done
  env_content+="DJANGO_DEBUG=False"$'\n'
  env_content+="SECURE_HSTS_SECONDS=31536000"$'\n'
  env_content+="SECURE_SSL_REDIRECT=True"$'\n'
  env_content+="SESSION_COOKIE_SECURE=True"$'\n'
  env_content+="CSRF_COOKIE_SECURE=True"$'\n'

  echo ""
  echo "--- Django Superuser ---"
  echo "(saved as .env)"
  for var in "${SUPERUSER_VARS[@]}"; do
    val=$(prompt_var "$var")
    env_content+="$(format_var "$var" "$val")"$'\n'
  done

  printf "%s" "$env_content" > ~/.env
  echo "[OK] .env created in ~/.env"
}

# --------------- read helpers ---------------
read_env_value() {
  local key="$1"
  grep "^${key}=" ~/.env | cut -d'=' -f2- | xargs | tr -d "'"
}

read_env_array() {
  local key="$1"
  local raw
  raw=$(read_env_value "$key")
  IFS=',' read -ra ADDR <<< "$raw"
  printf "%s\n" "${ADDR[@]}"
}

# --------------- configure nginx ---------------
configure_nginx() {
  local hosts server_name bucket region

  mapfile -t hosts < <(read_env_array "DJANGO_ALLOWED_HOSTS")
  server_name="${hosts[0]}"
  [ -n "${hosts[1]:-}" ] && server_name+=" ${hosts[1]}"

  bucket=$(read_env_value "AWS_STORAGE_BUCKET_NAME")
  region=$(read_env_value "AWS_S3_REGION_NAME")

  sudo tee /etc/nginx/sites-available/"$CONTAINER_NAME" > /dev/null << EOF
server {
    listen 80;
    server_name ${server_name};

    location /static/ {
        return 301 https://${bucket}.s3.${region}.amazonaws.com/;
    }

    location / {
        include proxy_params;
        proxy_pass http://127.0.0.1:${HOST_PORT};
    }
}
EOF

  sudo ln -sf /etc/nginx/sites-available/"$CONTAINER_NAME" \
             /etc/nginx/sites-enabled/
  sudo rm -f /etc/nginx/sites-enabled/default
  sudo nginx -t
  sudo systemctl restart nginx
}

# --------------- system packages ---------------
ensure_system_packages() {
  sudo apt update && sudo apt upgrade -y

if ! command -v docker &> /dev/null; then
    sudo apt install -y docker.io
    sudo systemctl enable --now docker
    sudo usermod -aG docker ubuntu
    echo "You need to log out and back in for Docker group to take effect."
    echo "Then re-run this script."
    exit 0
fi
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
    --env-file ~/.env \
    -v /home/ubuntu/staticfiles:/app/staticfiles \
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
    --env-file ~/.env \
    "$CONTAINER_NAME" python manage.py createsuperuser --noinput \
    || echo "[WARN] Superuser already exists (or creation failed)"
}

django_collectstatic() {
  echo "[..] Collecting static files..."
  docker exec "$CONTAINER_NAME" python manage.py collectstatic --noinput
}

# --------------- ufw ---------------
configure_firewall() {
  sudo ufw allow 22/tcp
  sudo ufw allow 80/tcp
  sudo ufw allow 443/tcp
  sudo ufw --force enable
}

# --------------- certbot ---------------
configure_ssl() {
  local first_host second_host certbot_domains email

  mapfile -t hosts < <(read_env_array "DJANGO_ALLOWED_HOSTS")
  first_host="${hosts[0]}"
  second_host="${hosts[1]:-}"

  certbot_domains="-d ${first_host}"
  [ -n "$second_host" ] && certbot_domains+=" -d ${second_host}"
  email=$(read_env_value "PERSONAL_EMAIL")

  sudo certbot --nginx ${certbot_domains} \
    --non-interactive --agree-tos \
    --email "$email" \
    --redirect

  sudo certbot renew --dry-run
}

# --------------- smoke test ---------------
smoke_test() {
  local first_host second_host

  mapfile -t hosts < <(read_env_array "DJANGO_ALLOWED_HOSTS")
  first_host="${hosts[0]}"
  second_host="${hosts[1]:-}"

  curl -I "https://${first_host}"
  [ -n "$second_host" ] && curl -I "https://${second_host}"
}

# ------------------ main ------------------
main() {
  parse_args "$@"

  ensure_system_packages
  write_env
  deploy_docker

  if [ "$SKIP_MIGRATIONS" = false ]; then
    django_migrate
  fi

  django_createsuperuser

  if [ "$SKIP_COLLECTSTATIC" = false ]; then
    django_collectstatic
  fi

  configure_nginx

  if [ "$NO_FIREWALL" = false ]; then
    configure_firewall
  fi

  if [ "$NO_SSL" = false ]; then
    configure_ssl
  fi

  smoke_test
}

main "$@"
