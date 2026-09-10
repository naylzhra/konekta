from fastapi import FastAPI

app = FastAPI(title="KONEKTA Forecasting Service")


@app.get("/health")
async def health() -> dict:
    return {"status": "ok", "service": "forecasting-service"}
