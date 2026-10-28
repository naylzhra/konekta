"""HTTP clients for the stateless pooling and stop evaluation services."""
import os

import httpx


class VirtualStopServiceUnavailable(Exception):
    pass


class ServiceClient:
    def __init__(self, base_url: str, timeout_s: float = 30.0) -> None:
        self.base_url = base_url.rstrip("/")
        self.timeout_s = timeout_s

    async def post(self, path: str, payload: dict) -> dict:
        try:
            async with httpx.AsyncClient(timeout=self.timeout_s) as client:
                response = await client.post(f"{self.base_url}{path}", json=payload)
            response.raise_for_status()
            return response.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise VirtualStopServiceUnavailable(path) from exc


def pooling_client() -> ServiceClient:
    return ServiceClient(os.getenv("POOLING_URL", "http://pooling-service:8000"))


def evaluation_client() -> ServiceClient:
    return ServiceClient(os.getenv("STOP_OPTIMIZATION_URL", "http://stop-optimization-service:8000"))
