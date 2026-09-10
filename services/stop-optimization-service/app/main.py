from fastapi import FastAPI

app = FastAPI(title="KONEKTA Stop Optimization Service")


@app.get("/health")
async def health() -> dict:
    return {"status": "ok", "service": "stop-optimization-service"}
