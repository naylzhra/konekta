# Postgres-backed user lookups for phone number + password auth.
from typing import Optional

from app.db import get_pool


async def get_user_by_phone(phone_number: str) -> Optional[dict]:
    pool = await get_pool()
    row = await pool.fetchrow(
        "SELECT id, phone_number, password_hash, role, status FROM users WHERE phone_number = $1",
        phone_number,
    )
    return dict(row) if row else None


async def create_user(phone_number: str, password_hash: str, role: str) -> dict:
    pool = await get_pool()
    row = await pool.fetchrow(
        """
        INSERT INTO users (phone_number, password_hash, role)
        VALUES ($1, $2, $3)
        RETURNING id, phone_number, role, status
        """,
        phone_number,
        password_hash,
        role,
    )
    return dict(row)


async def set_user_status(user_id: str, status: str) -> None:
    pool = await get_pool()
    await pool.execute("UPDATE users SET status = $1 WHERE id = $2", status, user_id)
