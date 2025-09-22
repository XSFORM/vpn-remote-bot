#!/bin/sh
# update_script.sh - минимальный обновлятор remote адреса VPN
# VERSION 6 (лог только при реальном изменении)
#
# ПЕРЕД ИСПОЛЬЗОВАНИЕМ ОБЯЗАТЕЛЬНО ЗАМЕНИ Remote URL НИЖЕ!

REMOTE_URL="http://YOUR_HOST_DOMAIN/remote.txt"   # <-- ЗАМЕНИ на свой домен
LAST_FILE="/etc/storage/vpn_last_remote_val"
RESTART_METHOD="toggle"      # toggle | none
SAVE_TO_FLASH=1              # 1 = сохранять через mtd_storage.sh save при изменении
LOCKDIR="/tmp/update_vpn_remote.lock"

NVRAM_KEY_MAIN="vpn_client_server"
NVRAM_KEY_PEER="vpnc_peer"   # оставь или сделай пустой если не нужен

log_update() {
    logger -t vpn-update "$*"
}

# --- блокировка ---
if ! mkdir "$LOCKDIR" 2>/dev/null; then
    exit 0
fi
trap 'rmdir "$LOCKDIR"' EXIT

# --- скачивание ---
TMP="/tmp/remote_new.$$"
wget -q -T 15 -O "$TMP" "$REMOTE_URL"
if [ ! -s "$TMP" ]; then
    rm -f "$TMP"
    exit 0
fi
NEW=$(tr -d '\r\n\t ' < "$TMP")
rm -f "$TMP"
[ -z "$NEW" ] && exit 0

# --- старое ---
if [ -f "$LAST_FILE" ]; then
    OLD=$(tr -d '\r\n\t ' < "$LAST_FILE")
else
    OLD=""
fi

# --- без изменений ---
if [ "$NEW" = "$OLD" ]; then
    exit 0
fi

# --- применение ---
echo "$NEW" > "$LAST_FILE"

if [ "$RESTART_METHOD" = "toggle" ]; then
    nvram set vpn_client_enable=0
    nvram set "$NVRAM_KEY_MAIN"="$NEW"
    [ -n "$NVRAM_KEY_PEER" ] && nvram set "$NVRAM_KEY_PEER"="$NEW"
    nvram commit
    sleep 2
    nvram set vpn_client_enable=1
    nvram commit
else
    nvram set "$NVRAM_KEY_MAIN"="$NEW"
    [ -n "$NVRAM_KEY_PEER" ] && nvram set "$NVRAM_KEY_PEER"="$NEW"
    nvram commit
fi

[ "$SAVE_TO_FLASH" -eq 1 ] && command -v mtd_storage.sh >/dev/null 2>&1 && mtd_storage.sh save 2>/dev/null

log_update "UPDATED: ${OLD:-<none>} -> $NEW"
exit 0