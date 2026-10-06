from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.bookings.dependencies import start_background, stop_background
from app.db import close_pool, get_pool
from app.routers import auth, bookings, consents, driver_stops, health
from app.websocket.manager import router as websocket_router


@asynccontextmanager
async def lifespan(_app: FastAPI):
    await get_pool()
    await start_background()
    yield
    await stop_background()
    await close_pool()


app = FastAPI(title="KONEKTA Gateway", lifespan=lifespan)

app.include_router(health.router)
app.include_router(auth.router)
app.include_router(bookings.router)
app.include_router(consents.router)
app.include_router(driver_stops.router)
app.include_router(websocket_router)
