# Shared WS message envelope (DESIGN.md §5.1): every message in both
# directions is {"type": str, "payload": {...}}.
import re
from typing import Any, Generic, Literal, TypeVar

from pydantic import BaseModel, ConfigDict, Field

PayloadT = TypeVar("PayloadT")

# e.g. "feeder:abc-123"
TOPIC_PATTERN = re.compile(r"^[a-z_]+:[A-Za-z0-9_-]{1,64}$")


class WsEnvelope(BaseModel, Generic[PayloadT]):
    model_config = ConfigDict(extra="forbid")

    type: str = Field(min_length=1, max_length=64)
    payload: PayloadT


class TopicPayload(BaseModel):
    topic: str = Field(pattern=TOPIC_PATTERN.pattern)


class ErrorPayload(BaseModel):
    code: str
    message: str


class IncomingMessage(WsEnvelope[dict[str, Any]]):
    type: Literal["subscribe", "unsubscribe", "ping"]
    payload: dict[str, Any] = Field(default_factory=dict)
