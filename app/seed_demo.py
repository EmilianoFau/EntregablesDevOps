"""Explicit, idempotent demo data. Never runs automatically or replaces entries."""
from datetime import timedelta

from sqlalchemy.dialects.postgresql import insert

from app.clock import journal_today
from app.database import SessionLocal
from app.models import JournalEntry, Mood


def main() -> None:
    today = journal_today()
    samples = [
        (1, Mood.AGRADECIDO, "Salí a caminar sin apuro y terminé encontrando un café nuevo. Me senté junto a la ventana, leí unas páginas y dejé el teléfono en el bolsillo. A veces un día lindo está hecho de cosas así de pequeñas.\n\nMe llevo esa pausa. Y las ganas de repetirla."),
        (3, Mood.FELIZ, "Hoy cocinamos algo rico con amigos. La receta no salió exactamente como esperábamos, pero nos reímos tanto que dio lo mismo.\n\nQuiero acordarme de la sobremesa, de la música bajita y de esa sensación de estar justo donde quería estar."),
    ]
    with SessionLocal.begin() as db:
        added = 0
        for days, mood, content in samples:
            statement = insert(JournalEntry).values(
                entry_date=today - timedelta(days=days), mood=mood, content=content
            ).on_conflict_do_nothing(index_elements=["entry_date"]).returning(JournalEntry.id)
            added += int(db.execute(statement).scalar_one_or_none() is not None)
    print(f"{added} entradas de ejemplo agregadas; las existentes se conservaron.")


if __name__ == "__main__":
    main()
