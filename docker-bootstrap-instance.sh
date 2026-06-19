#!/usr/bin/env bash
# =============================================================================
# docker-bootstrap-instance.sh
#
# Run once on provisioning a new instance, after docker-setup-env.sh .
#
# -- Phase 1: installs system packages (docker, nginx, certbot, ufw),
#             adds ubuntu to docker group, then EXITS requiring logout.
# -- Phase 2: after logout+login, run with --phase-2 to configure
#             nginx, ufw and certbot.
# =============================================================================
set -euo pipefail

# --------------- defaults ---------------
DEFAULT_CONTAINER_NAME="portfolio"
DEFAULT_HOST_PORT=8000
DEFAULT_ENV_FILE="$HOME/.env"

CONTAINER_NAME="$DEFAULT_CONTAINER_NAME"
HOST_PORT="$DEFAULT_HOST_PORT"
ENV_FILE="$DEFAULT_ENV_FILE"
PHASE_2=false

# --------------- usage ---------------
usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --container-name NAME  Container name (default: $DEFAULT_CONTAINER_NAME)
  --port PORT            Host port mapping (default: $DEFAULT_HOST_PORT)
  --env-file PATH        Path to .env file (default: $DEFAULT_ENV_FILE)
  --phase-2              Run phase 2 only (nginx, ufw, certbot).
                         Requires logout+login after phase 1.
  -h, --help             Show this help and exit

Examples:
  # Phase 1 (first run):
  ./docker-bootstrap-instance.sh

  # Log out, log back in, then:
  ./docker-bootstrap-instance.sh --phase-2

NOTE: requires ~/.env to exist (generated with docker-setup-env.sh).
EOF
  exit 0
}

# --------------- parse args ---------------
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --container-name)  CONTAINER_NAME="$2";  shift 2 ;;
      --port)            HOST_PORT="$2";       shift 2 ;;
      --env-file)        ENV_FILE="$2";        shift 2 ;;
      --phase-2)         PHASE_2=true;         shift   ;;
      -h|--help)         usage                         ;;
      *) echo "[ERROR] Unknown option: $1"; usage      ;;
    esac
  done
}

# --------------- error handling ---------------
handle_error() {
  local exit_code=$?
  local line_no=$1
  echo "[ERROR] docker-bootstrap-instance.sh - line ${line_no}:"
  echo "       command ended with code ${exit_code}"
  exit "${exit_code}"
}
trap 'handle_error $LINENO' ERR

# --------------- helpers --------------------
read_env_value() {
  local key="$1"
  grep "^${key}=" "$ENV_FILE" | cut -d'=' -f2- | xargs | tr -d "'"
}

read_env_array() {
  local key="$1"
  local raw
  raw=$(read_env_value "$key")
  IFS=',' read -ra ADDR <<< "$raw"
  printf "%s\n" "${ADDR[@]}"
}

# =============================================================================
# PHASE 1  —  system packages & docker group
# =============================================================================

phase1_install_packages() {
  echo ""
  echo "--- Phase 1: system packages ---"

  sudo apt update && sudo apt upgrade -y

  local packages=(
    docker.io
    nginx
    certbot
    python3-certbot-nginx
    ufw
  )

  sudo apt install -y "${packages[@]}"

  sudo systemctl enable --now docker
  sudo usermod -aG docker ubuntu

  echo ""
  echo "[OK] Phase 1 complete."
  echo ""
  echo "  ╔══════════════════════════════════════════════════╗"
  echo "  ║  LOG OUT and log back in for the Docker group   ║"
  echo "  ║  to take effect. Then run:                      ║"
  echo "  ║                                                  ║"
  echo "  ║    ./docker-bootstrap-instance.sh --phase-2      ║"
  echo "  ║                                                  ║"
  echo "  ║  to configure nginx, firewall and SSL.           ║"
  echo "  ╚══════════════════════════════════════════════════╝"
  echo ""
}

# =============================================================================
# PHASE 2  —  nginx, firewall, SSL
# =============================================================================

phase2_configure_nginx() {
  local hosts server_name bucket region

  if [ ! -f "$ENV_FILE" ]; then
    echo "[ERROR] $ENV_FILE not found. Run docker-setup-env.sh first."
    exit 1
  fi

  mapfile -t hosts < <(read_env_array "DJANGO_ALLOWED_HOSTS")
  server_name="${hosts[0]}"
  [ -n "${hosts[1]:-}" ] && server_name+=" ${hosts[1]}"

  bucket=$(read_env_value "AWS_STORAGE_BUCKET_NAME")
  region=$(read_env_value "AWS_S3_REGION_NAME")

  echo "[..] Configuring nginx for: ${server_name}"

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

  echo "[OK] nginx configured."
}

phase2_configure_firewall() {
  echo "[..] Configuring firewall..."
  sudo ufw allow 22/tcp
  sudo ufw allow 80/tcp
  sudo ufw allow 443/tcp
  sudo ufw --force enable
  sudo ufw status
  echo "[OK] Firewall configured."
}

phase2_configure_ssl() {
  local first_host second_host certbot_domains email

  if [ ! -f "$ENV_FILE" ]; then
    echo "[ERROR] $ENV_FILE not found. Run docker-setup-env.sh first."
    exit 1
  fi

  mapfile -t hosts < <(read_env_array "DJANGO_ALLOWED_HOSTS")
  first_host="${hosts[0]}"
  second_host="${hosts[1]:-}"

  certbot_domains="-d ${first_host}"
  [ -n "$second_host" ] && certbot_domains+=" -d ${second_host}"
  email=$(read_env_value "PERSONAL_EMAIL")

  echo "[..] Obtaining SSL certificate for: ${certbot_domains}"

  sudo certbot --nginx ${certbot_domains} \
    --non-interactive --agree-tos \
    --email "$email" \
    --redirect

  sudo certbot renew --dry-run

  echo "[OK] SSL configured."
}

phase2_run_all() {
  echo ""
  echo "--- Phase 2: nginx, firewall, SSL ---"

  phase2_configure_nginx
  phase2_configure_firewall
  phase2_configure_ssl

  echo ""
  echo "============================================="
  echo " Bootstrap complete!"
  echo " Next step:"
  echo "   ./docker-deploy.sh"
  echo "============================================="
}

# ------------------ main ------------------
main() {
  parse_args "$@"

  echo "============================================="
  echo " docker-bootstrap-instance.sh"
  echo "============================================="

  if [ "$PHASE_2" = true ]; then
    phase2_run_all
  else
    phase1_install_packages
  fi
}

main "$@"
