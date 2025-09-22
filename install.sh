#!/usr/bin/env bash
set -e

# ================== НАСТРОЙКИ / ПЕРЕМЕННЫЕ ==================
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${REPO_DIR}/.env"
SYSTEMD_UNIT="vpn-remote-bot.service"
SYSTEMD_PATH="/etc/systemd/system/${SYSTEMD_UNIT}"
VENV_DIR="${REPO_DIR}/.venv"

WEB_ROOT="${WEB_ROOT:-/var/www/html}"
REMOTE_FILE="${WEB_ROOT}/remote.txt"

ROUTER_SCRIPT_SRC="${REPO_DIR}/router/update_script.sh"
ROUTER_SCRIPT_DEST="${WEB_ROOT}/update_script.sh"

color() { printf "\033[%sm%s\033[0m\n" "$1" "$2"; }
info(){ color "36" "[INFO] $*"; }
warn(){ color "33" "[WARN] $*"; }
err(){ color "31" "[ERR ] $*" >&2; }
check_cmd() { command -v "$1" >/dev/null 2>&1 || { err "Не найдено: $1"; exit 1; }; }

if [[ $EUID -ne 0 ]]; then
  warn "Рекомендуется запуск от root."
fi

RECONFIG=0
if [[ "$1" == "--reconfigure" ]]; then
  RECONFIG=1
  info "Режим: пере-конфигурация"
fi

info "Установка системных пакетов (git, nginx, python3-venv)..."
apt update -y
apt install -y git nginx python3-venv

info "Проверка зависимостей..."
check_cmd python3
check_cmd systemctl
check_cmd nginx

PY_VER=$(python3 -c 'import sys; v=sys.version_info; print(f"{v.major}.{v.minor}")')
REQ_MINOR=10
MINOR=$(echo "$PY_VER" | cut -d. -f2)
if [[ "${PY_VER%%.*}" -lt 3 || $MINOR -lt $REQ_MINOR ]]; then
  warn "Рекомендуется Python >= 3.10 (найдено ${PY_VER})."
fi

if [[ $RECONFIG -eq 0 ]]; then
  info "Начальная установка"
fi

while true; do
  read -r -p "Введите домен сервера (HOST_DOMAIN) (например: vpn.example.com): " HOST_DOMAIN
  [[ -z "$HOST_DOMAIN" ]] && { warn "Пусто."; continue; }
  [[ ! "$HOST_DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]] && { warn "Недопустимые символы."; continue; }
  break
done

read -r -p "Telegram Bot Token: " BOT_TOKEN
[[ -z "$BOT_TOKEN" ]] && { err "Token пустой"; exit 1; }

read -r -p "Admin Telegram ID(s) (через запятую): " ADMIN_IDS
[[ -z "$ADMIN_IDS" ]] && { err "Admin IDs пустые"; exit 1; }

info "Подготовка WEB_ROOT: ${WEB_ROOT}"
mkdir -p "${WEB_ROOT}"

if [[ -f "${REMOTE_FILE}" ]]; then
  if [[ $RECONFIG -eq 1 ]]; then
    info "remote.txt уже есть — оставляю ($(cat "${REMOTE_FILE}" 2>/dev/null || echo '?'))."
  else
    info "Перезаписываю remote.txt на '${HOST_DOMAIN}'."
    echo "${HOST_DOMAIN}" > "${REMOTE_FILE}"
  fi
else
  info "Создание remote.txt со значением ${HOST_DOMAIN}"
  echo "${HOST_DOMAIN}" > "${REMOTE_FILE}"
fi
chmod 644 "${REMOTE_FILE}"

ln -sf "${REMOTE_FILE}" "${REPO_DIR}/remote.txt" || true

if [[ -f "${ROUTER_SCRIPT_SRC}" ]]; then
  info "Публикую update_script.sh -> ${ROUTER_SCRIPT_DEST}"
  cp "${ROUTER_SCRIPT_SRC}" "${ROUTER_SCRIPT_DEST}"
  chmod 644 "${ROUTER_SCRIPT_DEST}"
else
  warn "router/update_script.sh не найден — пропуск публикации."
fi

info "Создание / обновление .env..."
cat > "${ENV_FILE}" <<EOF
BOT_TOKEN=${BOT_TOKEN}
ADMIN_IDS=${ADMIN_IDS}
REMOTE_PATH=${REMOTE_FILE}
ALLOW_PLAIN_SET=true
HOST_DOMAIN=${HOST_DOMAIN}
EOF

info "Создание / обновление virtualenv..."
python3 -m venv "${VENV_DIR}"
# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"
pip install --upgrade pip
if [[ -f "${REPO_DIR}/bot/requirements.txt" ]]; then
  pip install -r "${REPO_DIR}/bot/requirements.txt"
else
  warn "bot/requirements.txt не найден — пропуск."
fi

if [[ -f "${REPO_DIR}/systemd/${SYSTEMD_UNIT}" ]]; then
  info "Установка systemd unit..."
  cp "${REPO_DIR}/systemd/${SYSTEMD_UNIT}" "${SYSTEMD_PATH}"
  sed -i "s|__REPO_DIR__|${REPO_DIR}|g" "${SYSTEMD_PATH}"
  sed -i "s|__VENV_DIR__|${VENV_DIR}|g" "${SYSTEMD_PATH}"
  systemctl daemon-reload
  systemctl enable --now "${SYSTEMD_UNIT}"
  info "Статус сервиса:"
  systemctl --no-pager status "${SYSTEMD_UNIT}" || true
else
  warn "systemd/${SYSTEMD_UNIT} нет — пропуск сервиса."
fi

FETCH_URL="http://${HOST_DOMAIN}/remote.txt"
SCRIPT_URL="http://${HOST_DOMAIN}/update_script.sh"
[ ! -f "${ROUTER_SCRIPT_DEST}" ] && SCRIPT_URL="(не опубликован)"

cat <<NEXT

========================================
УСТАНОВКА ЗАВЕРШЕНА
WEB_ROOT:                ${WEB_ROOT}
remote.txt путь:         ${REMOTE_FILE}
Текущее значение:        $(cat "${REMOTE_FILE}")
HOST_DOMAIN:             ${HOST_DOMAIN}
URL remote.txt:          ${FETCH_URL}
URL update_script.sh:    ${SCRIPT_URL}

Проверка:
  curl ${FETCH_URL}

Reconfigure:
  bash install.sh --reconfigure

(Если есть systemd unit)
  journalctl -u ${SYSTEMD_UNIT} -f
========================================

ДАЛЬШЕ (роутер):
1. Скопируй /etc/storage/update_script.sh из опубликованного ${SCRIPT_URL} (или вручную из репо).
2. chmod +x /etc/storage/update_script.sh
3. Run After Router Started:
   /etc/storage/update_script.sh &
4. Cron (пример):
   echo "*/10 * * * * /etc/storage/update_script.sh" > /etc/storage/cron/crontabs/admin
   nvram set crond_enable=1
   nvram commit
5. Меняешь remote.txt → смотри syslog: vpn-update: UPDATED: old -> new
========================================
NEXT