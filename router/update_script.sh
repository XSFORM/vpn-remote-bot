#!/bin/sh

NEW_REMOTE=$(wget -q -O - http://microlabsound.ru/remote.txt)

if [ -n "$NEW_REMOTE" ]; then
    nvram set vpn_client_server="$NEW_REMOTE"
    nvram set vpnc_peer="$NEW_REMOTE"
    nvram commit
    nvram set vpn_client_enable=0
    nvram commit
    sleep 3
    nvram set vpn_client_enable=1
    nvram commit
    logger -t vpn-update "Remote VPN обновлён на $NEW_REMOTE"
else
    logger -t vpn-update "Remote VPN не обновлён: пустой ответ"
fi