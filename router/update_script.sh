#!/bin/sh
# update_script.sh (universal auto-update) VERSION 2024-09
REMOTE_DOMAIN="microlabsound.ru"      # ← укажи свой домен!
PORT=$(nvram get vpnc_ov_port)
REMOTE_URL="http://$REMOTE_DOMAIN/remote.txt"
CONF="/etc/openvpn/client/client.conf"

# === 1. Получаем актуальный remote ===
if command -v wget >/dev/null 2>&1; then
  wget -q -O /etc/storage/remote.txt "$REMOTE_URL"
elif command -v curl >/dev/null 2>&1; then
  curl -fsSL "$REMOTE_URL" -o /etc/storage/remote.txt
fi

REMOTE_VAL=$(head -n1 /etc/storage/remote.txt | tr -d '\r\n\t ')
[ -z "$REMOTE_VAL" ] && REMOTE_VAL="$REMOTE_DOMAIN"

# === 2. Обновляем nvram ===
nvram set vpn_client_server="$REMOTE_VAL"
nvram set vpnc_peer="$REMOTE_VAL"

# === 3. Чистим remote-блок в vpn_client1_ovpn ===
nvram get vpn_client1_ovpn > /tmp/vpn_client1_ovpn.orig 2>/dev/null
grep -v -E '^(remote |# BEGIN AUTO REMOTES|# END AUTO REMOTES)' /tmp/vpn_client1_ovpn.orig > /tmp/vpn_client1_ovpn.clean
nvram set vpn_client1_ovpn="$(cat /tmp/vpn_client1_ovpn.clean)"

# === 4. Правим client.conf ===
cp -a "$CONF" "$CONF.bak.$(date +%s)"
if grep -q '^remote ' "$CONF"; then
  awk -v host="$REMOTE_VAL" -v port="$PORT" ' !done && /^remote / {print "remote " host " " port; done=1; next} {print}' "$CONF" > /tmp/cli.new && mv /tmp/cli.new "$CONF"
else
  sed -i "1a remote $REMOTE_VAL $PORT" "$CONF"
fi

# === 5. Коммитим nvram ===
nvram commit

# === 6. Перезапускаем OpenVPN ===
killall -q openvpn; sleep 2
/usr/sbin/openvpn --daemon openvpn-cli --cd /etc/openvpn/client --config client.conf
sleep 3

# === 7. Логируем и проверяем ===
logger -t vpn-update "UPDATED: remote set to $REMOTE_VAL:$PORT"