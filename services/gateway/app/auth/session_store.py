# TODO: active_trip_id is set/cleared here via set_active_trip(), but nothing calls it yet
import json
import os
import secrets
from typing import Optional

import redis.asyncio as redis

REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")
# refresh_session_ttl() resets this on every authenticated request
SESSION_TTL_SECONDS = 60 * 60 * 24

_redis: Optional[redis.Redis] = None


def _client() -> redis.Redis:
    global _redis
    if _redis is None:
        _redis = redis.from_url(REDIS_URL, decode_responses=True)
    return _redis


def _session_key(token: str) -> str:
    return f"session:{token}"


def _user_sessions_key(user_id: str) -> str:
    return f"user_sessions:{user_id}"


async def create_session(user_id: str, role: str) -> str:
    token = secrets.token_urlsafe(32)
    session = {
        "user_id": user_id,
        "role": role,
        "status": "active",
        "active_trip_id": None,
    }
    client = _client()
    await client.set(_session_key(token), json.dumps(session), ex=SESSION_TTL_SECONDS)
    await client.sadd(_user_sessions_key(user_id), token)
    await client.expire(_user_sessions_key(user_id), SESSION_TTL_SECONDS)
    return token


async def get_session(token: str) -> Optional[dict]:
    raw = await _client().get(_session_key(token))
    if raw is None:
        return None
    return json.loads(raw)


async def refresh_session_ttl(token: str) -> None:
    session = await get_session(token)
    if session is None:
        return
    client = _client()
    await client.expire(_session_key(token), SESSION_TTL_SECONDS)
    await client.expire(_user_sessions_key(session["user_id"]), SESSION_TTL_SECONDS)


async def delete_session(token: str) -> None:
    session = await get_session(token)
    client = _client()
    await client.delete(_session_key(token))
    if session is not None:
        await client.srem(_user_sessions_key(session["user_id"]), token)


async def set_active_trip(token: str, trip_id: Optional[str]) -> None:
    session = await get_session(token)
    if session is None:
        return
    session["active_trip_id"] = trip_id
    ttl = await _client().ttl(_session_key(token))
    await _client().set(_session_key(token), json.dumps(session), ex=ttl if ttl > 0 else SESSION_TTL_SECONDS)


async def _set_status_for_user(user_id: str, status: str) -> None:
    client = _client()
    tokens = await client.smembers(_user_sessions_key(user_id))
    for token in tokens:
        raw = await client.get(_session_key(token))
        if raw is None:
            continue
        session = json.loads(raw)
        session["status"] = status
        ttl = await client.ttl(_session_key(token))
        await client.set(_session_key(token), json.dumps(session), ex=ttl if ttl > 0 else SESSION_TTL_SECONDS)


async def suspend_user(user_id: str) -> None:
    await _set_status_for_user(user_id, "suspended")


async def reactivate_user(user_id: str) -> None:
    await _set_status_for_user(user_id, "active")
