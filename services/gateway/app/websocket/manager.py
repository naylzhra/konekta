"""
WebSocket connection manager stub.

TODO: wire this into pooling-service / stop-optimization-service events
once real-time feeder location and virtual-stop broadcasts are defined.
For now it just accepts connections and echoes messages back, so the
mobile app and dashboard have something to connect against.
"""
from typing import Dict

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

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
async def websocket_endpoint(websocket: WebSocket, client_id: str) -> None:
    await manager.connect(client_id, websocket)
    try:
        while True:
            data = await websocket.receive_text()
            # TODO: route incoming messages (location pings, ride requests,
            # virtual-stop subscriptions, etc.) instead of echoing.
            await manager.send_personal_message(client_id, f"echo: {data}")
    except WebSocketDisconnect:
        manager.disconnect(client_id)
