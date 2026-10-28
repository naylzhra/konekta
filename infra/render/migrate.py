"""Apply infra/db/migrations/*.sql to a remote Postgres (e.g. Render).

Locally, docker-compose runs these via docker-entrypoint-initdb.d on the
first boot of an empty volume. Render has no equivalent on the free plan,
so run this from your machine instead. Already-applied files are recorded
in `schema_migrations` and skipped, so it's safe to re-run after adding
new migrations.

Usage (needs `pip install asyncpg`):
    python infra/render/migrate.py "<Render External Database URL>"
"""
import asyncio
import sys
from pathlib import Path

import asyncpg

MIGRATIONS_DIR = Path(__file__).resolve().parents[1] / "db" / "migrations"


async def main(database_url: str) -> None:
    # Render's external URL requires TLS.
    conn = await asyncpg.connect(database_url, ssl="require")
    try:
        await conn.execute(
            "CREATE TABLE IF NOT EXISTS schema_migrations ("
            " filename TEXT PRIMARY KEY,"
            " applied_at TIMESTAMPTZ NOT NULL DEFAULT now())"
        )
        applied = {r["filename"] for r in await conn.fetch("SELECT filename FROM schema_migrations")}
        for path in sorted(MIGRATIONS_DIR.glob("*.sql")):
            if path.name in applied:
                print(f"skip   {path.name}")
                continue
            async with conn.transaction():
                await conn.execute(path.read_text(encoding="utf-8"))
                await conn.execute("INSERT INTO schema_migrations (filename) VALUES ($1)", path.name)
            print(f"apply  {path.name}")
    finally:
        await conn.close()


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    asyncio.run(main(sys.argv[1]))
