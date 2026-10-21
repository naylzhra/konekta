from typing import Literal, Optional
from uuid import UUID

import asyncpg

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel

from app.auth import session_store, user_store
from app.auth.dependencies import get_current_session, require_role
from app.auth.passwords import hash_password, verify_password
from app.db import get_pool
from app.feeders.repository import claim_feeder

router = APIRouter(prefix="/auth", tags=["auth"])


# Only mobile roles are self-registrable. "government" accounts (ops
# dashboard) and "admin" are provisioned out of band, see
# app/cli/create_user.py.
class RegisterRequest(BaseModel):
    phone_number: str
    password: str
    role: Literal["passenger", "driver"]
    # Drivers pick their feeder at registration (GET /corridors lists them);
    # required for drivers, rejected for passengers.
    feeder_id: Optional[str] = None


class LoginRequest(BaseModel):
    phone_number: str
    password: str


class AuthResponse(BaseModel):
    token: str
    role: str


class MeResponse(BaseModel):
    user_id: str
    role: str
    status: str
    phone_number: str
    display_name: Optional[str] = None


class ProfileUpdateRequest(BaseModel):
    phone_number: str
    display_name: Optional[str] = None


class PasswordChangeRequest(BaseModel):
    current_password: str
    new_password: str


@router.post("/register", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
async def register(payload: RegisterRequest) -> AuthResponse:
    existing = await user_store.get_user_by_phone(payload.phone_number)
    if existing is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Phone number already registered",
        )
    if (payload.role == "driver") != (payload.feeder_id is not None):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Feeder is required for drivers only",
        )
    password_hash = hash_password(payload.password)
    pool = await get_pool()
    async with pool.acquire() as conn, conn.transaction():
        user = await user_store.create_user(payload.phone_number, password_hash, payload.role, conn=conn)
        # Raising inside the transaction rolls back the new user too.
        if payload.feeder_id is not None and not await claim_feeder(conn, payload.feeder_id, user["id"]):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Feeder not available",
            )
    token = await session_store.create_session(str(user["id"]), user["role"])
    return AuthResponse(token=token, role=user["role"])


@router.post("/login", response_model=AuthResponse)
async def login(payload: LoginRequest) -> AuthResponse:
    user = await user_store.get_user_by_phone(payload.phone_number)
    if user is None or not verify_password(payload.password, user["password_hash"]):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid phone number or password",
        )
    if user["status"] == "suspended":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account suspended",
        )
    token = await session_store.create_session(str(user["id"]), user["role"])
    return AuthResponse(token=token, role=user["role"])


@router.get("/me", response_model=MeResponse)
async def me(session: dict = Depends(get_current_session)) -> MeResponse:
    profile = await user_store.get_profile(session["user_id"])
    if profile is None:
        raise HTTPException(status_code=404, detail="Account not found")
    return MeResponse(
        user_id=str(profile["id"]), role=profile["role"], status=profile["status"],
        phone_number=profile["phone_number"], display_name=profile["display_name"],
    )


@router.patch("/me", response_model=MeResponse)
async def update_me(payload: ProfileUpdateRequest, session: dict = Depends(require_role("passenger", "driver"))) -> MeResponse:
    phone = payload.phone_number.strip()
    name = payload.display_name.strip() if payload.display_name else None
    if not phone.startswith("+62") or not phone[3:].isdigit() or not 10 <= len(phone[3:]) <= 12:
        raise HTTPException(status_code=422, detail="Invalid phone number")
    if name is not None and len(name) > 80:
        raise HTTPException(status_code=422, detail="Name is too long")
    try:
        profile = await user_store.update_profile(session["user_id"], phone, name or None)
    except asyncpg.UniqueViolationError:
        raise HTTPException(status_code=409, detail="Phone number already registered") from None
    return MeResponse(
        user_id=str(profile["id"]), role=profile["role"], status=profile["status"],
        phone_number=profile["phone_number"], display_name=profile["display_name"],
    )


@router.post("/change-password", status_code=204)
async def change_password(payload: PasswordChangeRequest, session: dict = Depends(require_role("passenger", "driver"))) -> None:
    pool = await get_pool()
    row = await pool.fetchrow("SELECT password_hash FROM users WHERE id = $1", UUID(session["user_id"]))
    if row is None or not verify_password(payload.current_password, row["password_hash"]):
        raise HTTPException(status_code=400, detail="Current password is incorrect")
    if len(payload.new_password) < 8 or not any(c.isdigit() for c in payload.new_password) or not any(not c.isalnum() for c in payload.new_password):
        raise HTTPException(status_code=422, detail="Password must contain at least 8 characters, a digit and a special character")
    await user_store.update_password(session["user_id"], hash_password(payload.new_password))


@router.post("/logout")
async def logout(session: dict = Depends(get_current_session)) -> dict:
    await session_store.delete_session(session["token"])
    return {"status": "logged_out"}


@router.post("/users/{user_id}/suspend")
async def suspend_user(user_id: str, _: dict = Depends(require_role("admin"))) -> dict:
    await user_store.set_user_status(user_id, "suspended")
    await session_store.suspend_user(user_id)
    return {"status": "suspended", "user_id": user_id}


@router.post("/users/{user_id}/reactivate")
async def reactivate_user(user_id: str, _: dict = Depends(require_role("admin"))) -> dict:
    await user_store.set_user_status(user_id, "active")
    await session_store.reactivate_user(user_id)
    return {"status": "active", "user_id": user_id}
