# IoT GPS devices (ESP32 + NEO-6M) report their feeder's position here. Fixes
# go through the same store and `feeder.position` WS events as driver-app
# reports (routers/feeders.py); the service picks which source is published.
from fastapi import APIRouter, Depends, Header, HTTPException

from app.feeders.dependencies import get_feeder_service
from app.feeders.models import DevicePositionAccepted, DevicePositionReport, FeederError
from app.feeders.service import FeederTrackingService

router = APIRouter(tags=["devices"])


def _bearer_token(authorization: str) -> str:
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(
            401,
            detail={"code": "invalid_device", "message": "Invalid device credentials"},
            headers={"WWW-Authenticate": "Bearer"},
        )
    return token


@router.post("/devices/position", response_model=DevicePositionAccepted)
async def report_device_position(
    report: DevicePositionReport,
    x_device_id: str = Header(..., max_length=64),
    authorization: str = Header(...),
    service: FeederTrackingService = Depends(get_feeder_service),
) -> DevicePositionAccepted:
    token = _bearer_token(authorization)
    try:
        return await service.report_device_position(x_device_id, token, report)
    except FeederError as exc:
        raise HTTPException(exc.status_code, detail={"code": exc.code.value, "message": exc.message}) from exc
