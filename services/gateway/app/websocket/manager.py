# TODO: wire this into pooling-service events once real-time feeder location and virtual-stop broadcasts are defined.

from typing import Dict

from fastapi import APIRouter, Query, WebSocket, WebSocketDisconnect, status

from app.auth.session_store import get_session, refresh_session_ttl

router = APIRouter()


class ConnectionManager:
    """Tracks active WebSocket connections keyed by client_id."""

    def __init__(self) -> None:
        self.active_connections: Dict[str, WebSocket] = {}

    async def connect(self, client_id: str, websocket: WebSocket) -> None:
        await websocket.accept()
        self.active_connections[client_id] = websocket

    def disconnect(self, client_id: str) -> None:
        self.active_connections.pop(client_id, None)

    async def send_personal_message(self, client_id: str, message: str) -> None:
        websocket = self.active_connections.get(client_id)
        if websocket is not None:
            await websocket.send_text(message)

    async def broadcast(self, message: str) -> None:
        for websocket in self.active_connections.values():
            await websocket.send_text(message)


manager = ConnectionManager()


@router.websocket("/ws/{client_id}")
async def websocket_endpoint(websocket: WebSocket, client_id: str, token: str = Query(...)) -> None:
    session = await get_session(token)
    if session is None:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        return
    await refresh_session_ttl(token)

    await manager.connect(client_id, websocket)
    try:
        while True:
            data = await websocket.receive_text()
            # TODO: route incoming messages (location pings, ride requests, virtual-stop subscriptions, etc.) instead of echoing.
            await manager.send_personal_message(client_id, f"echo: {data}")
    except WebSocketDisconnect:
        manager.disconnect(client_id)
