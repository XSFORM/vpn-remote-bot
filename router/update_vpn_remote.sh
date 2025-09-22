#!/bin/sh
# update_vpn_remote.sh
# VERSION: 1.0.0
# Обновляет remote OpenVPN клиента на роутере:
#  - тянет значение из remote.txt (или принимает явно через $1)
#  - поддерживает host и host:port (IPv6 без поддержки порта в одной строке)
#  - чистит лишние remote в nvram blob (vpn_client1_ovpn)
#  - правит /etc/openvpn/client/client.conf
#  - мягко перезапускает openvpn (по умолчанию)
#
# Переменные, которые можно переопределять снаружи (export до вызова):
#   REMOTE_URL        - URL до remote.txt (если не хотите передавать значение аргументом)
#   DEFAULT_PORT      - fallback порт (если не найден в remote и nvram пуст)
#   RESTART_METHOD    - soft | toggle | none
#   SAVE_TO_FLASH     - 0/1 сохранить mtd_storage.sh save при изменении
#   NVRAM_KEY_MAIN    - ключ основного remote (vpn_client_server)
#   NVRAM_KEY_PEER    - дополнительный ключ (vpnc_peer) или пусто
#   CONF_PATH         - путь к client.conf
#   LAST_FILE         - файл с последним применённым значением (для сравнения)
#
# Принудительное обновление даже если значение не изменилось:
#   update_vpn_remote.sh --force
#
# Безопасность: одновременный запуск синхронизируется через lockdir.

REMOTE_ARG="$1"

REMOTE_URL="${REMOTE_URL:-}"
DEFAULT_PORT="${DEFAULT_PORT:-1194}"
RESTART_METHOD="${RESTART_METHOD:-soft}"   # soft|toggle|none
SAVE_TO_FLASH="${SAVE_TO_FLASH:-1}"
NVRAM_KEY_MAIN="${NVRAM_KEY_MAIN:-vpn_client_server}"
NVRAM_KEY_PEER="${NVRAM_KEY_PEER:-vpnc_peer}"
CONF_PATH="${CONF_PATH:-/etc/openvpn/client/client.conf}"
LAST_FILE="${LAST_FILE:-/etc/storage/vpn_last_remote_val}"
LOCKDIR="/tmp/update_vpn_remote.lock"
WGET_TIMEOUT="${WGET_TIMEOUT:-15}"

log() { logger -t vpn-update "$*"; }

# ---- lock ----
if ! mkdir "$LOCKDIR" 2>/dev/null; then
  exit 0
fi
trap 'rmdir "$LOCKDIR"' EXIT

# ---- получить текущее удалённое значение (REMOTE_RAW) ----
BOM_STRIP() {
  # убираем UTF-8 BOM если есть
  sed '1s/^\xEF\xBB\xBF//'
}

REMOTE_RAW=""
FORCE=0
if [ "$REMOTE_ARG" = "--force" ]; then
  FORCE=1
  REMOTE_ARG=""
elif [ "$REMOTE_ARG" = "-f" ]; then
  FORCE=1
  REMOTE_ARG=""
fi

if [ -n "$REMOTE_ARG" ]; then
  REMOTE_RAW="$REMOTE_ARG"
elif [ -n "$REMOTE_URL" ]; then
  TMP="/tmp/remote_val.$$"
  if command -v wget >/dev/null 2>&1; then
    wget -q -T "$WGET_TIMEOUT" -O "$TMP" "$REMOTE_URL" || REMOTE_RAW=""
  elif command -v curl >/dev/null 2>&1; then
    curl -fsSL --max-time "$WGET_TIMEOUT" "$REMOTE_URL" -o "$TMP" || REMOTE_RAW=""
  fi
  [ -s "$TMP" ] && REMOTE_RAW="$(BOM_STRIP < "$TMP" | head -n1 | tr -d '\r\n\t ' )"
  rm -f "$TMP"
fi

[ -z "$REMOTE_RAW" ] && exit 0

# ---- парс host[:port] ----
HOST_PART="$REMOTE_RAW"
PORT_PART=""

# IPv6 (очень примитивно) — если содержит ':' более одного раза и нет явного :порт (цифры в конце),
# просто оставляем как есть и возьмём порт из nvram или DEFAULT_PORT.
COLON_COUNT=$(printf "%s" "$REMOTE_RAW" | awk -F':' '{print NF-1}')
if [ "$COLON_COUNT" -eq 1 ]; then
  # host:port предполагаем
  HP_HOST="${REMOTE_RAW%%:*}"
  HP_PORT="${REMOTE_RAW##*:}"
  if echo "$HP_PORT" | grep -Eq '^[0-9]{1,5}$'; then
    HOST_PART="$HP_HOST"
    PORT_PART="$HP_PORT"
  fi
fi

# Валидация host (простейшая)
if ! echo "$HOST_PART" | grep -Eq '^[A-Za-z0-9._-]{1,253}$'; then
  # допускаем IP (v4) формой цифры/точки
  if ! echo "$HOST_PART" | grep -Eq '^[0-9.]{7,15}$'; then
    log "REJECT invalid remote string: $REMOTE_RAW"
    exit 0
  fi
fi

# Получим порт из nvram если ещё не определён
[ -z "$PORT_PART" ] && PORT_PART="$(nvram get vpnc_ov_port 2>/dev/null)"
[ -z "$PORT_PART" ] && PORT_PART="$DEFAULT_PORT"

# sanity порт
if ! echo "$PORT_PART" | grep -Eq '^[0-9]{1,5}$'; then
  PORT_PART="$DEFAULT_PORT"
fi

NEW_COMBINED="${HOST_PART}:${PORT_PART}"

# ---- сравнение с предыдущим ----
OLD_COMBINED=""
[ -f "$LAST_FILE" ] && OLD_COMBINED="$(cat "$LAST_FILE" 2>/dev/null | tr -d '\r\n\t ')"

if [ "$NEW_COMBINED" = "$OLD_COMBINED" ] && [ "$FORCE" -ne 1 ]; then
  exit 0
fi

# ---- правка client.conf ----
if [ -f "$CONF_PATH" ]; then
  # резервная копия ограниченно (только если изм.)
  TS=$(date +%s)
  cp -p "$CONF_PATH" "${CONF_PATH}.bak.$TS" 2>/dev/null

  if grep -q '^remote ' "$CONF_PATH"; then
    sed -i "0,/^remote /s#^remote .*#remote $HOST_PART $PORT_PART#" "$CONF_PATH"
  else
    sed -i "1a remote $HOST_PART $PORT_PART" "$CONF_PATH"
  fi
fi

# ---- чистим лишние remote в nvram blob ----
NV_BLOB=$(nvram get vpn_client1_ovpn 2>/dev/null | grep -v -E '^(remote |# BEGIN AUTO REMOTES|# END AUTO REMOTES)')
nvram set vpn_client1_ovpn="$NV_BLOB"

# ---- записываем nvram ключи ----
nvram set "$NVRAM_KEY_MAIN"="$HOST_PART"
[ -n "$NVRAM_KEY_PEER" ] && nvram set "$NVRAM_KEY_PEER"="$HOST_PART"

# Сохраняем последнее значение
echo "$NEW_COMBINED" > "$LAST_FILE"

# ---- commit / flash ----
nvram commit
[ "$SAVE_TO_FLASH" -eq 1 ] && command -v mtd_storage.sh >/dev/null 2>&1 && mtd_storage.sh save 2>/dev/null

# ---- рестарт ----
case "$RESTART_METHOD" in
  toggle)
    nvram set vpn_client_enable=0
    nvram commit
    sleep 2
    nvram set vpn_client_enable=1
    nvram commit
    ;;
  soft)
    killall -q openvpn
    sleep 2
    /usr/sbin/openvpn --daemon openvpn-cli --cd /etc/openvpn/client --config "$(basename "$CONF_PATH")"
    ;;
  none)
    ;;
  *)
    # неизвестное значение — fallback soft
    killall -q openvpn
    sleep 2
    /usr/sbin/openvpn --daemon openvpn-cli --cd /etc/openvpn/client --config "$(basename "$CONF_PATH")"
    ;;
esac

log "APPLIED: ${OLD_COMBINED:-<none>} -> $NEW_COMBINED (method=$RESTART_METHOD)"
exit 0