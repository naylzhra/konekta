from fastapi import FastAPI

from app.routers import health
from app.websocket.manager import router as websocket_router

app = FastAPI(title="KONEKTA Gateway")

app.include_router(health.router)
app.include_router(websocket_router)
