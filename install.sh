#!/usr/bin/env bash
set -e

# ============ ПЕРЕМЕННЫЕ ============
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${REPO_DIR}/.env"
SYSTEMD_UNIT="vpn-remote-bot.service"
SYSTEMD_PATH="/etc/systemd/system/${SYSTEMD_UNIT}"
VENV_DIR="${REPO_DIR}/.venv"

# Можно переопределить перед запуском: WEB_ROOT=/var/www/vpn-remote bash install.sh
WEB_ROOT="${WEB_ROOT:-/var/www/html}"
REMOTE_FILE="${WEB_ROOT}/remote.txt"

# ============ ВСПОМОГАТЕЛЬНЫЕ ============
color() { printf "\033[%sm%s\033[0m\n" "$1" "$2"; }
info(){ color "36" "[INFO] $*"; }
warn(){ color "33" "[WARN] $*"; }
err(){ color "31" "[ERR ] $*" >&2; }

check_cmd() { command -v "$1" >/dev/null 2>&1 || { err "Не найдено: $1"; exit 1; }; }

# ============ ПРОВЕРКИ ПРАВ ============
if [[ $EUID -ne 0 ]]; then
  warn "Рекомендуется запускать под root (или через sudo), иначе будут проблемы с установкой в systemd и записью в ${WEB_ROOT}."
fi

# ============ РЕЖИМ ============
RECONFIG=0
if [[ "$1" == "--reconfigure" ]]; then
  RECONFIG=1
  info "Режим: пере-конфигурация"
fi

# ============ СИСТЕМНЫЕ ПАКЕТЫ ============
info "Установка системных пакетов (git, nginx, python3-venv)..."
apt update -y
apt install -y git nginx python3-venv

# ============ ПРОВЕРКА КОМАНД ============
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

# ============ ВВОД ДАННЫХ ============
if [[ $RECONFIG -eq 0 ]]; then
  info "Начальная установка"
fi

while true; do
  read -r -p "Введите домен сервера (HOST_DOMAIN) (без http://, например: vpn.example.com): " HOST_DOMAIN
  if [[ -z "$HOST_DOMAIN" ]]; then
    warn "Домен не может быть пустым."; continue
  fi
  if [[ ! "$HOST_DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]]; then
    warn "Недопустимые символы. Разрешены: буквы, цифры, точка, дефис."; continue
  fi
  break
done

read -r -p "Telegram Bot Token: " BOT_TOKEN
[[ -z "$BOT_TOKEN" ]] && { err "Token не может быть пустым"; exit 1; }

read -r -p "Admin Telegram ID(s) (через запятую): " ADMIN_IDS
[[ -z "$ADMIN_IDS" ]] && { err "Admin IDs не могут быть пустыми"; exit 1; }

# ============ ПОДГОТОВКА WEB ROOT ============
info "Подготовка WEB_ROOT: ${WEB_ROOT}"
mkdir -p "${WEB_ROOT}"

if [[ -f "${REMOTE_FILE}" ]]; then
  if [[ $RECONFIG -eq 1 ]]; then
    info "remote.txt уже существует в ${REMOTE_FILE} — сохраняю текущее значение."
  else
    info "remote.txt уже существует. Перезаписываю значение на 'mydomain.com'."
    echo "mydomain.com" > "${REMOTE_FILE}"
  fi
else
  info "Создание remote.txt (значение: mydomain.com) в ${REMOTE_FILE}"
  echo "mydomain.com" > "${REMOTE_FILE}"
fi

chmod 644 "${REMOTE_FILE}"

# Создадим (или обновим) симлинк в репозитории для удобного просмотра:
ln -sf "${REMOTE_FILE}" "${REPO_DIR}/remote.txt"

# ============ .ENV ============
info "Создание / обновление .env..."
cat > "${ENV_FILE}" <<EOF
BOT_TOKEN=${BOT_TOKEN}
ADMIN_IDS=${ADMIN_IDS}
REMOTE_PATH=${REMOTE_FILE}
ALLOW_PLAIN_SET=true
HOST_DOMAIN=${HOST_DOMAIN}
EOF

# ============ VENV ============
info "Создание / обновление virtualenv..."
python3 -m venv "${VENV_DIR}"
# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"
pip install --upgrade pip
pip install -r "${REPO_DIR}/bot/requirements.txt"

# ============ SYSTEMD ============
info "Установка systemd unit..."
cp "${REPO_DIR}/systemd/${SYSTEMD_UNIT}" "${SYSTEMD_PATH}"
sed -i "s|__REPO_DIR__|${REPO_DIR}|g" "${SYSTEMD_PATH}"
sed -i "s|__VENV_DIR__|${VENV_DIR}|g" "${SYSTEMD_PATH}"

info "Перезагрузка systemd..."
systemctl daemon-reload
systemctl enable --now "${SYSTEMD_UNIT}"

info "Статус сервиса:"
systemctl --no-pager status "${SYSTEMD_UNIT}" || true

FETCH_URL="http://${HOST_DOMAIN}/remote.txt"

# ============ ИТОГ ============
cat <<NEXT

========================================
УСТАНОВКА ЗАВЕРШЕНА
WEB_ROOT:        ${WEB_ROOT}
remote.txt путь: ${REMOTE_FILE}
Текущее значение: $(cat "${REMOTE_FILE}")
HOST_DOMAIN:     ${HOST_DOMAIN}
URL для роутеров: ${FETCH_URL}

Проверь доступ:
  curl ${FETCH_URL}

Переконфигурация: bash install.sh --reconfigure
Логи: journalctl -u ${SYSTEMD_UNIT} -f

Если Nginx использует стандартный default-site с root /var/www/html — всё готово.
Если ты сменил WEB_ROOT, настрой серверный блок Nginx:
  server {
      listen 80;
      server_name ${HOST_DOMAIN};
      root ${WEB_ROOT};
      default_type text/plain;
      location = /remote.txt {
          add_header Cache-Control "no-cache";
          try_files /remote.txt =404;
      }
  }

========================================
NEXT