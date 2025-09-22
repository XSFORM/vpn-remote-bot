# VPN Remote Management

## Что делает
Позволяет менять адрес VPN (remote) через серверный `remote.txt` (и бота) и автоматически подтягивать его на роутерах. Лог появляется только при реальном изменении.

## Быстрая установка (одной командой)
```bash
git clone https://github.com/XSFORM/vpn-remote-bot.git && cd vpn-remote-bot && bash install.sh
```

## Установка сервера (по шагам)
```bash
bash install.sh
# или повторная конфигурация
bash install.sh --reconfigure
```

После установки:
- `http://HOST_DOMAIN/remote.txt` — текущее значение (домена или host:port).
- `http://HOST_DOMAIN/update_vpn_remote.sh` — основной скрипт (выкладывается/копируется вручную, либо через деплой).

## Новая архитектура (v7+)
Сделано разделение на:
1. `update_script.sh` (bootstrap) — лёгкая обёртка. Скачивает:
   - `update_vpn_remote.sh`
   - `remote.txt`
   Вызывает основной скрипт и используется в cron/старте.
2. `update_vpn_remote.sh` — основная логика:
   - Парс `host` или `host:port`
   - Чистка лишних `remote` в `vpn_client1_ovpn`
   - Правка `/etc/openvpn/client/client.conf`
   - Перезапуск OpenVPN (soft kill/start по умолчанию; можно toggle)
   - Запись значения в nvram (commit только при изменении)
   - Лог `vpn-update: APPLIED: old -> new`

## Формат remote.txt
Первая строка:
```
example.com
```
или
```
example.com:443
```
Если порт не указан — берётся из `nvram get vpnc_ov_port` или `DEFAULT_PORT` (по умолчанию 1194).

## Подготовка роутера (актуально для новой схемы)
1. Скопировать (или вставить) содержимое `router/update_script.sh` в `/etc/storage/update_script.sh`.
2. Внутри поменять `REMOTE_DOMAIN` (или задать через export в старте).
3. Сделать исполняемым:
   ```sh
   chmod +x /etc/storage/update_script.sh
   ```
4. В "Run After Router Started" добавить:
   ```sh
   /etc/storage/update_script.sh &
   ```
5. Cron (пример каждые 2 минуты):
   ```sh
   echo "*/2 * * * * /etc/storage/update_script.sh" > /etc/storage/cron/crontabs/admin
   nvram set crond_enable=1
   nvram commit
   ```

После первого запуска bootstrap скачает `update_vpn_remote.sh` и `remote.txt`.

## Поведение
- Если значение remote не изменилось — тишина.
- Если изменилось:
  ```
  vpn-update: APPLIED: <старое> -> host:port (method=soft)
  ```
- Bootstrap при обновлении основной логики:
  ```
  vpn-update-bootstrap: main script updated (md5 ...)
  ```

## Настройки (переменные)
Можно экспортировать перед запуском bootstrap (в старте):
| Переменная        | По умолчанию              | Значение |
|-------------------|---------------------------|----------|
| REMOTE_DOMAIN     | microlabsound.ru          | Домен сервера |
| BASE_URL          | http://$REMOTE_DOMAIN     | База URL |
| REMOTE_URL        | $BASE_URL/remote.txt      | Источник значения |
| MAIN_URL          | $BASE_URL/update_vpn_remote.sh | Где брать основной скрипт |
| RESTART_METHOD    | soft                      | soft / toggle / none |
| SAVE_TO_FLASH     | 1                         | mtd_storage.sh save при изменении |
| DEFAULT_PORT      | 1194                      | Используется если порт не указан |
| NVRAM_KEY_MAIN    | vpn_client_server         | Основной ключ |
| NVRAM_KEY_PEER    | vpnc_peer                 | Второй ключ (можно пустым) |

## Ручное принудительное применение
```sh
/export RESTART_METHOD=soft
/etc/storage/script/update_vpn_remote.sh --force
```

## Бот
Команда `/set host` или `/set host:port` обновляет `remote.txt`.
Через ≤ интервал cron роутеры подхватят.

## Примечание
`remote.txt` в репозитории хранить не обязательно — главное, чтобы по HTTP он выдавался. Основной скрипт можно обновлять централизованно (роутеры сами скачивают свежую версию).
