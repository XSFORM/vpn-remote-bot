import os
import logging
import asyncio
import re
from pathlib import Path
from dotenv import load_dotenv
from aiogram import Bot, Dispatcher, types
from aiogram.filters import Command

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger("vpn-remote-bot")

load_dotenv()

BOT_TOKEN = os.getenv("BOT_TOKEN")
ADMIN_IDS_RAW = os.getenv("ADMIN_IDS", "")
REMOTE_PATH = Path(os.getenv("REMOTE_PATH", "remote.txt"))
ALLOW_PLAIN_SET = os.getenv("ALLOW_PLAIN_SET", "true").lower() == "true"
HOST_DOMAIN = os.getenv("HOST_DOMAIN", "").strip()

if not BOT_TOKEN:
    raise RuntimeError("BOT_TOKEN не задан в .env")
if not ADMIN_IDS_RAW:
    raise RuntimeError("ADMIN_IDS не заданы в .env")

ADMIN_IDS = set()
for part in ADMIN_IDS_RAW.split(","):
    p = part.strip()
    if p.isdigit():
        ADMIN_IDS.add(int(p))

bot = Bot(token=BOT_TOKEN)
dp = Dispatcher()

REMOTE_PATH.parent.mkdir(parents=True, exist_ok=True)
if not REMOTE_PATH.exists():
    REMOTE_PATH.write_text("mydomain.com", encoding="utf-8")

REMOTE_REGEX = re.compile(r"^[A-Za-z0-9._:-]{3,255}$")

def is_admin(user_id: int) -> bool:
    return user_id in ADMIN_IDS

def read_remote() -> str:
    try:
        return REMOTE_PATH.read_text(encoding="utf-8").strip()
    except Exception as e:
        logger.error("Ошибка чтения remote.txt: %s", e)
        return "(error)"

def write_remote(value: str) -> bool:
    try:
        REMOTE_PATH.write_text(value.strip(), encoding="utf-8")
        logger.info("remote.txt обновлён: %s", value)
        return True
    except Exception as e:
        logger.error("Ошибка записи remote.txt: %s", e)
        return False

def validate_remote(value: str) -> bool:
    value = value.strip()
    if " " in value:
        return False
    return bool(REMOTE_REGEX.match(value))

def help_text() -> str:
    base = (
        "Команды:\n"
        "/status — текущее значение remote\n"
        "/set <value> — установить новое значение (admins)\n"
        "/help — помощь\n"
    )
    if HOST_DOMAIN:
        base += f"URL для роутеров: http://{HOST_DOMAIN}/remote.txt\n"
    return base

@dp.message(Command("start"))
async def cmd_start(message: types.Message):
    await message.answer("VPN Remote Bot готов.\n" + help_text())

@dp.message(Command("help"))
async def cmd_help(message: types.Message):
    await message.answer(help_text())

@dp.message(Command("status"))
async def cmd_status(message: types.Message):
    current = read_remote()
    await message.answer(f"Текущее значение: {current}")

@dp.message(Command("set"))
async def cmd_set(message: types.Message):
    if not is_admin(message.from_user.id):
        await message.answer("Нет доступа.")
        return
    parts = message.text.strip().split(maxsplit=1)
    if len(parts) < 2:
        await message.answer("Использование: /set new.remote.value")
        return
    new_value = parts[1].strip()
    if not validate_remote(new_value):
        await message.answer("Неверный формат. Разрешены: буквы, цифры, . _ - :")
        return
    if write_remote(new_value):
        await message.answer(f"Обновлено: {new_value}")
    else:
        await message.answer("Ошибка записи.")

@dp.message()
async def fallback(message: types.Message):
    if not ALLOW_PLAIN_SET:
        return
    if not is_admin(message.from_user.id):
        return
    candidate = message.text.strip()
    if not candidate or candidate.startswith("/"):
        return
    if validate_remote(candidate):
        if write_remote(candidate):
            await message.reply(f"Обновлено: {candidate}")
        else:
            await message.reply("Ошибка записи.")
    else:
        await message.reply("Неверный формат. Используй /set <value>.")

async def main():
    logger.info("Старт бота...")
    await dp.start_polling(bot)

if __name__ == "__main__":
    asyncio.run(main())