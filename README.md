# VPN Remote Updater Bot

Телеграм‑бот для удалённого управления файлом `remote.txt`, который читают роутеры (Padavan/Asus) для получения актуального адреса VPN сервера.

## Термины

| Понятие | Что это | Откуда берётся |
|---------|---------|----------------|
| HOST_DOMAIN | Домен сервера, по которому роутеры скачивают `remote.txt` (например: `vpn.example.com`) | Вводится вручную при установке (`install.sh`) |
| remote.txt (содержимое) | Текущее значение VPN удалённого адреса (IP или домен) | Меняется через Telegram‑бота |
| Начальное значение remote.txt | `mydomain.com` (плейсхолдер) | Создаётся установщиком |

## Возможности
- `/set <домен|ip>` — обновляет `remote.txt`
- `/status` — показывает текущее значение
- Ограничение прав по списку админов
- Автозапуск через systemd
- Установка одним скриптом `install.sh`
- Возможность принимать просто текст от админа как новое значение (если включено `ALLOW_PLAIN_SET`)

## Установка

```bash
git clone https://github.com/XSFORM/vpn-remote-bot.git
cd vpn-remote-bot
bash install.sh
```

Во время установки будут заданы вопросы:
1. HOST_DOMAIN (домен, где будет доступен файл remote.txt), например: `vpn.example.com`
2. Telegram Bot Token
3. Admin Telegram ID(s) — список ID через запятую

После установки:
- `remote.txt` содержит `mydomain.com`
- Сервис бота запущен
- Можно сменить значение через `/set <новый_адрес>`

## Пример обращения роутера

Роутер периодически загружает (HTTP):
```
http://HOST_DOMAIN/remote.txt
```

## Пример скрипта для Padavan (замени HOST_DOMAIN на свой)

```sh
#!/bin/sh
NEW_REMOTE=$(wget -q -O - http://HOST_DOMAIN/remote.txt)
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
```

## Команды бота

| Команда | Описание |
|---------|----------|
| /start  | Краткая информация |
| /help   | Подсказка |
| /status | Текущее значение remote.txt |
| /set VALUE | Установить новое значение (только админы) |

(Если `ALLOW_PLAIN_SET=true` — простое сообщение от админа без команды тоже установит значение.)

## Повторная конфигурация

```bash
bash install.sh --reconfigure
```

## Логи

```bash
journalctl -u vpn-remote-bot.service -f
```

## Файлы

| Файл | Назначение |
|------|------------|
| install.sh | Установщик / пере-конфигуратор |
| remote.txt | Текущее значение remote (изначально `mydomain.com`) |
| bot/bot.py | Код Telegram‑бота |
| systemd/vpn-remote-bot.service | Unit для systemd |
| .env | Переменные окружения (создаётся установщиком) |
| .env.example | Шаблон структуры (без значений) |

## Безопасность
- В `ADMIN_IDS` указываются только доверенные Telegram ID.
- Можно ограничить доступ к `remote.txt` (фаервол / basic auth / IP allowlist).
- Для шифрованного трафика можно настроить HTTPS (Nginx + TLS), но это опционально.

## Обновление кода

```bash
git pull
bash install.sh --reconfigure
```

## Удаление

```bash
systemctl disable --now vpn-remote-bot.service
rm /etc/systemd/system/vpn-remote-bot.service
systemctl daemon-reload
# (опционально) удалить директорию репозитория
```
