import json

import pytest
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from app.main import app
from app.websocket import manager as manager_module
from app.websocket.manager import ConnectionManager


class FakeSocket:
    def __init__(self, fail: bool = False) -> None:
        self.sent: list[dict] = []
        self.fail = fail

    async def accept(self) -> None:
        pass

    async def send_text(self, message: str) -> None:
        if self.fail:
            raise RuntimeError("socket closed")
        self.sent.append(json.loads(message))


@pytest.fixture
def hub() -> ConnectionManager:
    return ConnectionManager()


async def test_send_to_user_reaches_all_of_that_users_connections_only(hub):
    phone, tablet, other = FakeSocket(), FakeSocket(), FakeSocket()
    await hub.connect("c1", phone, user_id="u1")
    await hub.connect("c2", tablet, user_id="u1")
    await hub.connect("c3", other, user_id="u2")

    await hub.send_to_user("u1", "booking.updated", {"id": "b1", "version": 2})

    expected = [{"type": "booking.updated", "payload": {"id": "b1", "version": 2}}]
    assert phone.sent == expected
    assert tablet.sent == expected
    assert other.sent == []


async def test_topic_subscribe_publish_unsubscribe(hub):
    a, b = FakeSocket(), FakeSocket()
    await hub.connect("a", a, user_id="u1")
    await hub.connect("b", b, user_id="u2")
    await hub.handle_message("a", json.dumps({"type": "subscribe", "payload": {"topic": "feeder:f-1"}}))

    await hub.publish("feeder:f-1", "feeder.position", {"feeder_id": "f-1"})
    assert a.sent == [{"type": "feeder.position", "payload": {"feeder_id": "f-1"}}]
    assert b.sent == []

    await hub.handle_message("a", json.dumps({"type": "unsubscribe", "payload": {"topic": "feeder:f-1"}}))
    await hub.publish("feeder:f-1", "feeder.position", {"feeder_id": "f-1"})
    assert len(a.sent) == 1


async def test_disconnect_cleans_user_and_topic_indexes(hub):
    socket = FakeSocket()
    await hub.connect("c1", socket, user_id="u1")
    hub.subscribe("c1", "feeder:f-1")
    hub.disconnect("c1")

    await hub.send_to_user("u1", "booking.updated", {})
    await hub.publish("feeder:f-1", "feeder.position", {})
    assert socket.sent == []
    assert hub._user_clients == {} and hub._topic_clients == {}  # noqa: SLF001


async def test_failed_send_drops_dead_socket_without_breaking_fanout(hub):
    dead, alive = FakeSocket(fail=True), FakeSocket()
    await hub.connect("dead", dead, user_id="u1")
    await hub.connect("alive", alive, user_id="u1")

    await hub.send_to_user("u1", "booking.updated", {"v": 1})

    assert alive.sent == [{"type": "booking.updated", "payload": {"v": 1}}]
    assert "dead" not in hub.active_connections


async def test_reconnect_with_same_client_id_replaces_old_socket(hub):
    old, new = FakeSocket(), FakeSocket()
    await hub.connect("c1", old, user_id="u1")
    hub.subscribe("c1", "feeder:f-1")
    await hub.connect("c1", new, user_id="u1")

    await hub.send_to_user("u1", "booking.updated", {})
    assert old.sent == [] and len(new.sent) == 1
    # subscriptions don't survive a reconnect; the client resubscribes
    await hub.publish("feeder:f-1", "feeder.position", {})
    assert len(new.sent) == 1


@pytest.mark.parametrize(
    "raw",
    ["not json", json.dumps({"type": "shout", "payload": {}}), json.dumps({"type": "subscribe"})],
)
async def test_bad_messages_get_error_not_crash(hub, raw):
    socket = FakeSocket()
    await hub.connect("c1", socket, user_id="u1")
    await hub.handle_message("c1", raw)
    assert socket.sent[0]["type"] == "error"


async def test_invalid_topic_rejected(hub):
    socket = FakeSocket()
    await hub.connect("c1", socket, user_id="u1")
    await hub.handle_message("c1", json.dumps({"type": "subscribe", "payload": {"topic": "../../etc"}}))
    assert socket.sent == [{"type": "error", "payload": {"code": "invalid_topic", "message": "Invalid topic"}}]


# --- endpoint (auth via session store, patched) -------------------------------


@pytest.fixture
def patched_sessions(monkeypatch):
    async def get_session(token: str):
        return {"user_id": "u-ws", "role": "passenger"} if token == "good" else None

    async def refresh_session_ttl(token: str) -> None:
        return None

    monkeypatch.setattr(manager_module, "get_session", get_session)
    monkeypatch.setattr(manager_module, "refresh_session_ttl", refresh_session_ttl)


def test_endpoint_rejects_bad_token(patched_sessions):
    client = TestClient(app)
    with pytest.raises(WebSocketDisconnect) as exc_info:
        with client.websocket_connect("/ws/c1?token=bad") as ws:
            ws.receive_text()
    assert exc_info.value.code == 1008


def test_endpoint_ping_pong_and_user_index(patched_sessions):
    client = TestClient(app)
    with client.websocket_connect("/ws/c-ping?token=good") as ws:
        ws.send_text(json.dumps({"type": "ping"}))
        assert json.loads(ws.receive_text()) == {"type": "pong", "payload": {}}
        assert "c-ping" in manager_module.manager._user_clients["u-ws"]  # noqa: SLF001
    assert "c-ping" not in manager_module.manager.active_connections
