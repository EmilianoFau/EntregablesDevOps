from datetime import date, datetime
from zoneinfo import ZoneInfo

from app.config import get_settings


def journal_today() -> date:
    """The server owns the diary date, independently of the browser clock."""
    return datetime.now(ZoneInfo(get_settings().journal_timezone)).date()
