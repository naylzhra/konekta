# Single WS hub shared by booking and live tracking (DESIGN.md §5.1).
# Connections are indexed by the session's user_id so events can be sent per
# user, plus topic subscriptions (e.g. "feeder:<id>") for broadcast feeds.
#
# TODO: state is in-process memory. Running more than one gateway
# worker/replica needs a shared fan-out (e.g. Redis pub/sub) behind
# send_to_user()/publish().
# TODO: topic subscriptions are not authorized per user yet; any session can
# subscribe to any feeder topic.

import json
import logging
from typing import Any, Dict, Optional, Set

from fastapi import APIRouter, Query, WebSocket, WebSocketDisconnect, status
from pydantic import BaseModel, ValidationError

from app.auth.session_store import get_session, refresh_session_ttl
from app.websocket.envelope import ErrorPayload, IncomingMessage, TopicPayload

logger = logging.getLogger(__name__)

router = APIRouter()


def _encode(type_: str, payload: Any) -> str:
    if isinstance(payload, BaseModel):
        payload = payload.model_dump(mode="json")
    return json.dumps({"type": type_, "payload": payload})


class ConnectionManager:
    """Tracks active WebSocket connections by client_id, user_id and topic."""

    def __init__(self) -> None:
        self.active_connections: Dict[str, WebSocket] = {}
        self._client_user: Dict[str, str] = {}
        self._user_clients: Dict[str, Set[str]] = {}
        self._topic_clients: Dict[str, Set[str]] = {}
        self._client_topics: Dict[str, Set[str]] = {}

    async def connect(self, client_id: str, websocket: WebSocket, user_id: Optional[str] = None) -> None:
        await websocket.accept()
        previous = self.active_connections.get(client_id)
        if previous is not None and previous is not websocket:
            # same client reconnected; drop the stale socket's indexes
            self.disconnect(client_id)
        self.active_connections[client_id] = websocket
        if user_id is not None:
            self._client_user[client_id] = user_id
            self._user_clients.setdefault(user_id, set()).add(client_id)

    def disconnect(self, client_id: str) -> None:
        self.active_connections.pop(client_id, None)
        user_id = self._client_user.pop(client_id, None)
        if user_id is not None:
            clients = self._user_clients.get(user_id)
            if clients is not None:
                clients.discard(client_id)
                if not clients:
                    del self._user_clients[user_id]
        for topic in self._client_topics.pop(client_id, set()):
            subscribers = self._topic_clients.get(topic)
            if subscribers is not None:
                subscribers.discard(client_id)
                if not subscribers:
                    del self._topic_clients[topic]

    def subscribe(self, client_id: str, topic: str) -> None:
        self._topic_clients.setdefault(topic, set()).add(client_id)
        self._client_topics.setdefault(client_id, set()).add(topic)

    def unsubscribe(self, client_id: str, topic: str) -> None:
        subscribers = self._topic_clients.get(topic)
        if subscribers is not None:
            subscribers.discard(client_id)
            if not subscribers:
                del self._topic_clients[topic]
        topics = self._client_topics.get(client_id)
        if topics is not None:
            topics.discard(topic)

    async def _send(self, client_id: str, message: str) -> None:
        websocket = self.active_connections.get(client_id)
        if websocket is None:
            return
        try:
            await websocket.send_text(message)
        except Exception:  # noqa: BLE001 -- a dead socket must not break fan-out
            logger.info("dropping websocket connection after failed send")
            self.disconnect(client_id)

    async def send_personal_message(self, client_id: str, message: str) -> None:
        await self._send(client_id, message)

    async def send_event(self, client_id: str, type_: str, payload: Any) -> None:
        await self._send(client_id, _encode(type_, payload))

    async def send_to_user(self, user_id: str, type_: str, payload: Any) -> None:
        message = _encode(type_, payload)
        for client_id in list(self._user_clients.get(user_id, ())):
            await self._send(client_id, message)

    async def publish(self, topic: str, type_: str, payload: Any) -> None:
        message = _encode(type_, payload)
        for client_id in list(self._topic_clients.get(topic, ())):
            await self._send(client_id, message)

    async def broadcast(self, message: str) -> None:
        for client_id in list(self.active_connections):
            await self._send(client_id, message)

    async def handle_message(self, client_id: str, raw: str) -> None:
        try:
            message = IncomingMessage.model_validate_json(raw)
        except ValidationError:
            await self.send_event(
                client_id, "error", ErrorPayload(code="invalid_message", message="Unsupported message")
            )
            return
        if message.type == "ping":
            await self.send_event(client_id, "pong", {})
            return
        try:
            topic = TopicPayload.model_validate(message.payload).topic
        except ValidationError:
            await self.send_event(client_id, "error", ErrorPayload(code="invalid_topic", message="Invalid topic"))
            return
        if message.type == "subscribe":
            self.subscribe(client_id, topic)
        else:
            self.unsubscribe(client_id, topic)


manager = ConnectionManager()


@router.websocket("/ws/{client_id}")
async def websocket_endpoint(websocket: WebSocket, client_id: str, token: str = Query(...)) -> None:
    session = await get_session(token)
    if session is None:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        return
    await refresh_session_ttl(token)

    await manager.connect(client_id, websocket, user_id=session["user_id"])
    try:
        while True:
            data = await websocket.receive_text()
            await manager.handle_message(client_id, data)
    except WebSocketDisconnect:
        if manager.active_connections.get(client_id) is websocket:
            manager.disconnect(client_id)
