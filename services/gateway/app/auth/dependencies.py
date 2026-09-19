from fastapi import Depends, Header, HTTPException, status

from app.auth.session_store import get_session, refresh_session_ttl


# resolves the token to a session
async def get_current_session(authorization: str = Header(...)) -> dict:
    if not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or malformed Authorization header",
        )
    token = authorization.removeprefix("Bearer ")
    session = await get_session(token)
    if session is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired session",
        )
    await refresh_session_ttl(token)
    return {**session, "token": token}


# used for action that requires acc that are not suspended 
# -> called when starting new trip (should verify if account is banner or not)
async def require_not_suspended(session: dict = Depends(get_current_session)) -> dict:
    if session["status"] == "suspended" and not session.get("active_trip_id"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account suspended",
        )
    return session


def require_role(*roles: str):
    async def _check(session: dict = Depends(get_current_session)) -> dict:
        if session["role"] not in roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Insufficient role",
            )
        return session

    return _check
