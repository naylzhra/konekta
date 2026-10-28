"""Automatic scan only proposes when fresh weekly demand reaches the threshold."""
import asyncio
from datetime import datetime, timedelta, timezone

from app.virtual_stops import background


class _Connection:
    def __init__(self, count, newest, last_window_end=None):
        self.count = count
        self.newest = newest
        self.last_window_end = last_window_end
        self.unlocked = False

    async def fetchval(self, query, *args):
        if "pg_try_advisory_lock" in query:
            return True
        return self.last_window_end

    async def fetchrow(self, query, *args):
        return {"requests": self.count, "newest": self.newest}

    async def execute(self, query, *args):
        if "pg_advisory_unlock" in query:
            self.unlocked = True


class _Acquire:
    def __init__(self, connection):
        self.connection = connection

    async def __aenter__(self):
        return self.connection

    async def __aexit__(self, *args):
        return False


class _Pool:
    def __init__(self, connection):
        self.connection = connection

    def acquire(self):
        return _Acquire(self.connection)


def test_scan_requires_ten_requests_and_new_demand(monkeypatch):
    now = datetime(2026, 10, 23, tzinfo=timezone.utc)
    calls = []

    async def fake_run(*args, **kwargs):
        calls.append(kwargs)
        return {"candidates": 1}

    monkeypatch.setattr(background, "run_virtual_stops", fake_run)
    below = _Connection(9, now - timedelta(hours=1))
    assert asyncio.run(background.scan_once(_Pool(below), now)) is None
    assert below.unlocked
    old = _Connection(10, now - timedelta(hours=1), now - timedelta(minutes=30))
    assert asyncio.run(background.scan_once(_Pool(old), now)) is None
    fresh = _Connection(10, now - timedelta(minutes=1), now - timedelta(minutes=30))
    assert asyncio.run(background.scan_once(_Pool(fresh), now)) == {"candidates": 1}
    assert fresh.unlocked
    assert calls[0]["pooling_params"]["min_pts"] == background.config.REQUEST_THRESHOLD
    assert calls[0]["evaluation_params"]["min_stop_spacing_m"] == 300
    assert calls[0]["triggered_by"] is None
