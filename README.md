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
- `http://HOST_DOMAIN/remote.txt` — текущий адрес (значение перезаписывается при первой установке доменом HOST_DOMAIN).
- `http://HOST_DOMAIN/update_script.sh` — (если файл есть в репо) скрипт для роутера.

## Подготовка роутера
1. Скачать или скопировать содержимое `router/update_script.sh` в `/etc/storage/update_script.sh`.
2. Внутри заменить:
   ```sh
   REMOTE_URL="http://YOUR_HOST_DOMAIN/remote.txt"
   ```
3. Сделать исполняемым:
   ```sh
   chmod +x /etc/storage/update_script.sh
   ```
4. Добавить в "Run After Router Started":
   ```sh
   /etc/storage/update_script.sh &
   ```
5. Cron (пример каждые 10 минут):
   ```sh
   echo "*/10 * * * * /etc/storage/update_script.sh" > /etc/storage/cron/crontabs/admin
   nvram set crond_enable=1
   nvram commit
   ```

## Поведение
- Если адрес не изменился — тишина.
- При изменении: строка в syslog
  ```
  vpn-update: UPDATED: <старый> -> <новый>
  ```
- Перезапуск клиента выполняется через toggle (0→1). Можно отключить:
  ```sh
  RESTART_METHOD="none"
  ```

## Настройки в скрипте роутера
| Переменная       | Значение             | Назначение                          |
|------------------|----------------------|-------------------------------------|
| REMOTE_URL       | URL до remote.txt    | Источник адреса                     |
| RESTART_METHOD   | toggle / none        | Перезапуск клиента                  |
| SAVE_TO_FLASH    | 1 / 0                | Сохранение в постоянную память      |
| NVRAM_KEY_MAIN   | ключ nvram           | Основной remote параметр            |
| NVRAM_KEY_PEER   | ключ nvram (опц.)    | Второй (если нужен)                 |

## Обновление remote
Меняешь содержимое `remote.txt` (ботом или вручную) → при следующем cron‑запуске роутер применит и залогирует.

## Примечание
`remote.txt` в репо хранить не обязательно (install.sh создаёт его в WEB_ROOT и делает симлинк). Если не нужен симлинк — можно убрать соответствующую строку в скрипте установки.

---