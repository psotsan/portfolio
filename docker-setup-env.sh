#!/usr/bin/env bash
# =============================================================================
# docker-setup-env.sh
#
# Interactively generates/updates ~/.env
# Run once on provisioning instance or when var envs change.
# =============================================================================
set -euo pipefail

# --------------- defaults ---------------
DEFAULT_ENV_FILE="$HOME/.env"
ENV_FILE="$DEFAULT_ENV_FILE"

# --------------- usage ---------------
usage() {
  cat <<EOF
Usage: $(basename "$0") [--env-file PATH]

Options:
  --env-file PATH    Path to .env file (default: $DEFAULT_ENV_FILE)
  -h, --help         Show this help and exit
EOF
  exit 0
}

# --------------- parse args ---------------
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --env-file)  ENV_FILE="$2";  shift 2 ;;
      -h|--help)   usage                    ;;
      *) echo "[ERROR] Unknown option: $1"; usage ;;
    esac
  done
}

# --------------- error handling ---------------
handle_error() {
  local exit_code=$?
  local line_no=$1
  echo "[ERROR] docker-setup-env.sh - line ${line_no}:"
  echo "       command ended with code ${exit_code}"
  exit "${exit_code}"
}
trap 'handle_error $LINENO' ERR

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
  printf "%s=%s" "$var" "$val"
}

write_env() {
  local var val
  local secret_key
  local env_content=""

  echo ""
  echo "--- Django Settings ---"

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
  env_content+="USE_S3=True"$'\n'

  echo ""
  echo "--- Django Superuser ---"
  for var in "${SUPERUSER_VARS[@]}"; do
    val=$(prompt_var "$var")
    if [ "$var" = "DJANGO_SUPERUSER_PASSWORD" ]; then
      env_content+="${var}='${val}'"$'\n'
    else
      env_content+="${var}=${val}"$'\n'
    fi
  done

  printf "%s" "$env_content" > "$ENV_FILE"
  echo ""
  echo "[OK] .env created at: ${ENV_FILE}"
}

# ------------------ main ------------------
main() {
  parse_args "$@"

  echo "============================================="
  echo " docker-setup-env.sh"
  echo " Generate interactive .env file"
  echo "============================================="

  if [ -f "$ENV_FILE" ]; then
    echo ""
    echo "  [WARN] ${ENV_FILE} already exists."
    read -r -p "  Overwrite? [y/N] " reply
    case "$reply" in
      [yY]|[yY][eE][sS]) ;;
      *) echo "  Aborted."; exit 0 ;;
    esac
  fi

  write_env
}

main "$@"
