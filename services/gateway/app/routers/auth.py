"""
Auth endpoints: register/login/logout, and admin suspend/reactivate.

Credentials are phone number + password. No OTP verification of phone
ownership -- that's a real feature (SMS provider integration) intentionally
left out of this mockup stage; phone_number here is just a login
identifier, not a verified-owned number.

TODO: no admin provisioning flow exists -- /register only allows
passenger/driver. Create admin accounts by inserting into the users table
directly for now.
"""
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel

from app.auth import session_store, user_store
from app.auth.dependencies import get_current_session, require_role
from app.auth.passwords import hash_password, verify_password

router = APIRouter(prefix="/auth", tags=["auth"])


class RegisterRequest(BaseModel):
    phone_number: str
    password: str
    role: Literal["passenger", "driver"] # TODO: add governor


class LoginRequest(BaseModel):
    phone_number: str
    password: str


class AuthResponse(BaseModel):
    token: str
    role: str


@router.post("/register", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
async def register(payload: RegisterRequest) -> AuthResponse:
    existing = await user_store.get_user_by_phone(payload.phone_number)
    if existing is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Phone number already registered",
        )
    password_hash = hash_password(payload.password)
    user = await user_store.create_user(payload.phone_number, password_hash, payload.role)
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
