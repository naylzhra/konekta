# KONEKTA

Demand-based adaptive feeder mobility system for public transit in Bandung,
Indonesia. Riders' demand gets pooled into virtual stops, feeder vehicles get
dispatched to serve them, and stop placement adapts over time based on
observed demand.

This repo is currently a **skeleton**: every service boots and exposes a
`/health` endpoint, but no business logic (real clustering, scoring,
forecasting, or dispatch) is implemented yet.

## Architecture

```
apps/
  (root)         Flutter mobile app (pubspec.yaml, lib/, android/) — single codebase, passenger + driver roles only
  dashboard/     React + Vite ops dashboard — Mapbox GL (map) + Recharts (charts) — government role only

services/
  gateway/                     FastAPI — REST + WebSocket entrypoint for apps
  pooling-service/             DBSCAN clustering + weighted centroid + OSRM client
  stop-optimization-service/   Heuristic scoring for virtual stop placement
  forecasting-service/         XGBoost demand forecasting
  osrm-mock/                   Temporary routing service standing in for OSRM

infra/
  docker/        docker-compose.yml for local dev
  railway/        deploy config (placeholder)
  db/             Postgres/PostGIS migrations + seed data

packages/
  shared-models/  Shared Pydantic models (not yet wired into services)
  shared-utils/   Shared Python utilities (not yet wired into services)

docs/
  bpmn/           Process diagrams (placeholder)
```

Data flow (once implemented): mobile app sends ride requests through
**gateway** → **pooling-service** clusters nearby demand (DBSCAN) and computes
a weighted centroid, snapped to the road network via an OSRM-compatible
client → **stop-optimization-service** scores candidate virtual stops
(demand density, route-deviation cost, time-since-last-served) →
**forecasting-service** predicts demand to help pre-position feeders →
**gateway** pushes live updates (feeder location, assigned stop) to
mobile/dashboard over WebSocket. **Redis** (GEO commands) holds live feeder
positions; **Postgres/PostGIS** is the system of record.

### osrm-mock — temporary, pending real Bandung map data

We don't yet have the real Bandung `.osm.pbf` extract processed into
`.osrm` files (that's a separate offline pipeline for later). Until then,
`services/osrm-mock` is a lightweight FastAPI service that mimics OSRM's
`/route/v1/{profile}/{coordinates}` response shape: it returns a
straight-line path through the given waypoints with a fake
duration/distance derived from haversine distance and an assumed average
speed.

`pooling-service`'s OSRM client (`app/osrm_client.py`) reads its target
from the `OSRM_BASE_URL` env var, which defaults to `osrm-mock`. Once the
real Bandung map data is processed and a real OSRM instance is deployed,
switching over is just changing `OSRM_BASE_URL` — no code changes needed.

## Roles & which client they use

| Role        | Client                   | How the account is created                      |
|-------------|--------------------------|-------------------------------------------------|
| `passenger` | Mobile app               | Self-register (`POST /auth/register`)           |
| `driver`    | Mobile app               | Self-register (`POST /auth/register`)           |
| `government`| Web dashboard            | `python -m app.cli.create_user` (gateway)       |
| `admin`     | — (API only)             | `python -m app.cli.create_user` (gateway)       |

`/auth/register` only accepts `passenger`/`driver`. Both clients log in via
`POST /auth/login` and reject roles that aren't theirs (logging the session
back out): the mobile app rejects anything but passenger/driver, the
dashboard anything but government. Create a government account with:

```bash
docker compose -f infra/docker/docker-compose.yml exec gateway python -m app.cli.create_user --phone +6281234567890 --role government
```

The dashboard calls the gateway from the browser, so its origin must be in
the gateway's `CORS_ORIGINS` (defaults to `http://localhost:5173`, vite's
dev server).

## Running locally

Prerequisites: Docker + Docker Compose.

```bash
cp .env.example .env
docker-compose -f infra/docker/docker-compose.yml up --build
```

This brings up: `gateway` (:8000), `pooling-service` (:8001),
`stop-optimization-service` (:8002), `forecasting-service` (:8003),
`osrm-mock` (:5001), `postgres` (:5432, with PostGIS enabled via
`infra/db/migrations/001_init.sql`), and `redis` (:6379).

Verify everything's up:

```bash
curl http://localhost:8000/health
curl http://localhost:8001/health
curl http://localhost:8002/health
curl http://localhost:8003/health
curl http://localhost:5001/health
```

### Running the frontend apps (outside Docker, for now)

**Dashboard:**

```bash
cd apps/dashboard
cp .env.example .env   # set VITE_MAPBOX_TOKEN
npm install
npm run dev
```

**Mobile (Flutter):**

The `apps/` folder currently only contains the Dart source
(`pubspec.yaml` + `lib/`) — no platform (`android/`/`ios/`) folders yet.
Generate them once, then run as usual:

```bash
cd apps
flutter create .      # adds android/, ios/, web/ scaffolding around the existing lib/
flutter pub get
flutter run
```

The API client in `lib/core/api/api_client.dart` defaults to
`http://10.0.2.2:8000` (the Android emulator's alias for the host's
localhost) and hits gateway's `/health` endpoint.

## Repo conventions

- Each Python service is independently deployable: its own
  `requirements.txt` and `Dockerfile`, entrypoint at `app/main.py`, exposing
  at minimum a `GET /health`.
- `packages/shared-models` and `packages/shared-utils` are scaffolded but
  not yet installed into any service — intended to be pulled in via
  `pip install -e ../../packages/...` once there's real shared code to
  dedupe.
- No business logic is implemented yet. Every non-trivial module under
  `app/` has a `TODO` comment describing what real implementation is
  expected to do.


2. Restart Docker Desktop. Kalau masih error input/output, pakai Troubleshoot (ikon 🐞) → Restart.
3. Bersihkan sisa build Docker yang gagal:
docker builder prune -f
docker image prune -f
4. Build ulang:
$env:COMPOSE_PARALLEL_LIMIT=1
docker compose -f infra/docker/docker-compose.yml up --build

Catatan:
- Kalau tidak sedang butuh forecasting, cukup nyalakan service yang dibutuhkan saja. Ini
  menghemat ±1 GB:
docker compose -f infra/docker/docker-compose.yml up --build postgres redis osrm-mock gateway
pooling-service
- Kalau setelah ruang dikosongkan Docker tetap error I/O, kemungkinan virtual disk-nya sudah
  rusak. Pakai Troubleshoot → Clean / Purge data. Semua image dan volume Docker akan terhapus,
  termasuk data Postgres lokal, tapi data itu bisa dibuat ulang dari migration.          
✻ Churned for 36s · done 9:18 PM                                                                
──────────────────────────────────────── 1 new message ────────────────────────────────────────                                                                                             cap: You're trying to get the KONEKTA services running in Docker, but the build failed
  because drive C: is almost full (about 19 MB free). Next, free up 10–20 GB on C:, restart
  Docker Desktop, and rebuild. (disable recaps in /config)
                                                         ✔ Update installed · Restart to apply
────────────────────────────────────────────────────────────────────────────────────────────────
❯ udah dikosongin, sekarang errornya apa