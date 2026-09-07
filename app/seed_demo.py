"""Adds two example entries to the JSON file when their dates are free."""
from datetime import timedelta

from app.clock import journal_today
from app.repository import get_repository
from app.schemas import EntryCreate, Mood


def main() -> None:
    repository = get_repository()
    today = journal_today()
    samples = [
        (1, Mood.AGRADECIDO, "Salí a caminar sin apuro y encontré un café nuevo."),
        (3, Mood.FELIZ, "Cocinamos algo rico con amigos y nos quedamos charlando."),
    ]
    added = 0
    for days, mood, content in samples:
        entry_date = today - timedelta(days=days)
        if repository.get_by_date(entry_date) is None:
            repository.create(EntryCreate(content=content, mood=mood), entry_date)
            added += 1
    print(f"{added} entradas de ejemplo agregadas; las existentes se conservaron.")


if __name__ == "__main__":
    main()
