import os
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.bookings.dependencies import start_background, stop_background
from app.db import close_pool, get_pool
from app.virtual_stops.background import start_background as start_virtual_stop_scan, stop_background as stop_virtual_stop_scan
from app.routers import auth, bookings, consents, dashboard, devices, driver_stops, feeders, health, journey, virtual_stops
from app.websocket.manager import router as websocket_router


@asynccontextmanager
async def lifespan(_app: FastAPI):
    pool = await get_pool()
    await start_background()
    start_virtual_stop_scan(pool)
    yield
    await stop_virtual_stop_scan()
    await stop_background()
    await close_pool()


app = FastAPI(title="KONEKTA Gateway", lifespan=lifespan)

# The ops dashboard (apps/dashboard) calls the gateway from the browser.
# Mobile clients aren't subject to CORS.
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("CORS_ORIGINS", "http://localhost:5173").split(","),
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health.router)
app.include_router(auth.router)
app.include_router(bookings.router)
app.include_router(journey.router)
app.include_router(consents.router)
app.include_router(driver_stops.router)
app.include_router(feeders.router)
app.include_router(devices.router)
app.include_router(virtual_stops.router)
app.include_router(dashboard.router)
app.include_router(websocket_router)
