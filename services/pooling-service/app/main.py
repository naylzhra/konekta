from fastapi import FastAPI

app = FastAPI(title="KONEKTA Pooling Service")


@app.get("/health")
async def health() -> dict:
    return {"status": "ok", "service": "pooling-service"}
