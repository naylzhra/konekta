# Postgres-backed user lookups for phone number + password auth.
from typing import Optional
from uuid import UUID

import asyncpg

from app.db import get_pool


async def get_user_by_phone(phone_number: str) -> Optional[dict]:
    pool = await get_pool()
    row = await pool.fetchrow(
        "SELECT id, phone_number, password_hash, role, status FROM users WHERE phone_number = $1",
        phone_number,
    )
    return dict(row) if row else None


async def create_user(
    phone_number: str, password_hash: str, role: str, conn: Optional[asyncpg.Connection] = None
) -> dict:
    """Pass `conn` to create the user inside a caller's transaction."""
    executor = conn if conn is not None else await get_pool()
    row = await executor.fetchrow(
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


async def get_profile(user_id: str) -> Optional[dict]:
    pool = await get_pool()
    row = await pool.fetchrow(
        "SELECT id, phone_number, display_name, role, status FROM users WHERE id = $1",
        UUID(user_id),
    )
    return dict(row) if row else None


async def update_profile(user_id: str, phone_number: str, display_name: Optional[str]) -> dict:
    pool = await get_pool()
    row = await pool.fetchrow(
        """UPDATE users SET phone_number = $2, display_name = $3 WHERE id = $1
        RETURNING id, phone_number, display_name, role, status""",
        UUID(user_id), phone_number, display_name,
    )
    return dict(row)


async def update_password(user_id: str, password_hash: str) -> None:
    pool = await get_pool()
    await pool.execute("UPDATE users SET password_hash = $2 WHERE id = $1", UUID(user_id), password_hash)
