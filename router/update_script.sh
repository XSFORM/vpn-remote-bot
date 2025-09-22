#!/bin/sh
# update_script.sh (bootstrap) VERSION 7
#
# Задача:
#   1. Скачать/обновить основной скрипт update_vpn_remote.sh
#   2. Скачать remote.txt
#   3. Вызвать основной скрипт
#
# Настрой:
REMOTE_DOMAIN="${REMOTE_DOMAIN:-microlabsound.ru}"   # <-- поменяй при необходимости
BASE_URL="${BASE_URL:-http://$REMOTE_DOMAIN}"
REMOTE_URL="${REMOTE_URL:-$BASE_URL/remote.txt}"
MAIN_URL="${MAIN_URL:-$BASE_URL/update_vpn_remote.sh}"

SCRIPT_DIR="/etc/storage/script"
MAIN_SCRIPT="$SCRIPT_DIR/update_vpn_remote.sh"
REMOTE_LOCAL="/etc/storage/remote.txt"
TMP_MAIN="/tmp/update_vpn_remote.sh.$$"
TMP_REMOTE="/tmp/remote.txt.$$"
WGET_TIMEOUT="${WGET_TIMEOUT:-15}"
LOCKDIR="/tmp/update_vpn_boot.lock"

# Флаги для основного скрипта можно экспортировать тут (пример):
# export RESTART_METHOD="soft"
# export SAVE_TO_FLASH=1

log() { logger -t vpn-update-bootstrap "$*"; }

# lock
if ! mkdir "$LOCKDIR" 2>/dev/null; then exit 0; fi
trap 'rmdir "$LOCKDIR"' EXIT

mkdir -p "$SCRIPT_DIR"

fetch() {
  URL="$1"
  OUT="$2"
  if command -v wget >/dev/null 2>&1; then
    wget -q -T "$WGET_TIMEOUT" -O "$OUT" "$URL" || return 1
  elif command -v curl >/dev/null 2>&1; then
    curl -fsSL --max-time "$WGET_TIMEOUT" "$URL" -o "$OUT" || return 1
  else
    return 1
  fi
  [ -s "$OUT" ] || return 1
  return 0
}

# 1. update main script (только если отличается по md5)
if fetch "$MAIN_URL" "$TMP_MAIN"; then
  NEW_MD5=$(md5sum "$TMP_MAIN" | awk '{print $1}')
  OLD_MD5=""
  [ -f "$MAIN_SCRIPT" ] && OLD_MD5=$(md5sum "$MAIN_SCRIPT" | awk '{print $1}')
  if [ "$NEW_MD5" != "$OLD_MD5" ]; then
    cp -f "$TMP_MAIN" "$MAIN_SCRIPT"
    chmod +x "$MAIN_SCRIPT"
    log "main script updated (md5 $OLD_MD5 -> $NEW_MD5)"
  fi
fi
rm -f "$TMP_MAIN"

# 2. remote.txt
if fetch "$REMOTE_URL" "$TMP_REMOTE"; then
  # убираем BOM и чистим
  sed -i '1s/^\xEF\xBB\xBF//' "$TMP_REMOTE"
  head -n1 "$TMP_REMOTE" | tr -d '\r\n\t ' > "$REMOTE_LOCAL.tmp"
  if [ -s "$REMOTE_LOCAL.tmp" ]; then
    mv -f "$REMOTE_LOCAL.tmp" "$REMOTE_LOCAL"
  else
    rm -f "$REMOTE_LOCAL.tmp"
  fi
fi
rm -f "$TMP_REMOTE"

# 3. вызвать основной
if [ -x "$MAIN_SCRIPT" ]; then
  # передаём значение напрямую (чтобы не зависеть от сетевых сбоев внутри основного),
  # берем из только что скачанного remote.txt
  VAL=$(head -n1 "$REMOTE_LOCAL" 2>/dev/null | tr -d '\r\n\t ')
  if [ -n "$VAL" ]; then
    "$MAIN_SCRIPT" "$VAL"
  else
    "$MAIN_SCRIPT"
  fi
fi

exit 0