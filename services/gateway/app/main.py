from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.db import close_pool, get_pool
from app.routers import auth, health
from app.websocket.manager import router as websocket_router


@asynccontextmanager
async def lifespan(_app: FastAPI):
    await get_pool()
    yield
    await close_pool()


app = FastAPI(title="KONEKTA Gateway", lifespan=lifespan)

app.include_router(health.router)
app.include_router(auth.router)
app.include_router(websocket_router)
