# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

KONEKTA: a demand-based adaptive feeder mobility system for public transit in
Bandung, Indonesia. Riders' demand gets pooled into virtual stops, feeder
vehicles get dispatched to serve them, and stop placement adapts over time
based on observed demand.

**This repo is currently a skeleton.** Every service boots and exposes a
`GET /health` endpoint, but no business logic (real clustering, scoring,
forecasting, or dispatch) is implemented yet. Non-trivial modules under
`app/` are placeholders with a `TODO` comment describing what the real
implementation is expected to do — check for these before assuming a
function is production logic.

## Architecture

```
apps/
  mobile/        Flutter mobile app (pubspec.yaml, lib/, android/) — single codebase, passenger + driver roles only
  dashboard/     React + Vite ops dashboard — Mapbox GL (map) + Recharts (charts) — government role only

services/
  gateway/                     FastAPI — REST + WebSocket entrypoint for apps
  pooling-service/             DBSCAN clustering + weighted centroid + OSRM client
  stop-optimization-service/   Heuristic scoring for virtual stop placement
  forecasting-service/         XGBoost demand forecasting
  osrm-mock/                   Temporary routing service standing in for OSRM

infra/
  docker/        docker-compose.yml for local dev
  railway/       deploy config (placeholder)
  db/            Postgres/PostGIS migrations + seed data

packages/
  shared-models/  Shared Pydantic models (not yet wired into any service)
  shared-utils/   Shared Python utilities (not yet wired into any service)
```

**Data flow** (once implemented): mobile app sends ride requests through
**gateway** → **pooling-service** clusters nearby demand (DBSCAN) and computes
a weighted centroid, snapped to the road network via an OSRM-compatible
client → **stop-optimization-service** scores candidate virtual stops
(demand density, route-deviation cost, time-since-last-served) →
**forecasting-service** predicts demand to help pre-position feeders →
**gateway** pushes live updates (feeder location, assigned stop) to
mobile/dashboard over WebSocket. **Redis** (GEO commands) holds live feeder
positions; **Postgres/PostGIS** is the system of record.

### osrm-mock — temporary, pending real Bandung map data

There's no real Bandung `.osm.pbf` extract processed into `.osrm` files yet
(that's a separate offline pipeline for later). Until then,
`services/osrm-mock` is a lightweight FastAPI service mimicking OSRM's
`/route/v1/{profile}/{coordinates}` response shape: it returns a
straight-line path through the given waypoints with a fake duration/distance
derived from haversine distance and an assumed average speed.

`pooling-service`'s OSRM client (`app/osrm_client.py`) reads its target from
the `OSRM_BASE_URL` env var, defaulting to `osrm-mock`. Switching to a real
OSRM instance later is just changing `OSRM_BASE_URL` — no code changes
needed.

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

Brings up: `gateway` (:8000), `pooling-service` (:8001),
`stop-optimization-service` (:8002), `forecasting-service` (:8003),
`osrm-mock` (:5001), `postgres` (:5432, PostGIS enabled via
`infra/db/migrations/001_init.sql`), and `redis` (:6379).

Verify:

```bash
curl http://localhost:8000/health
curl http://localhost:8001/health
curl http://localhost:8002/health
curl http://localhost:8003/health
curl http://localhost:5001/health
```

### Dashboard (outside Docker)

```bash
cd apps/dashboard
cp .env.example .env   # set VITE_MAPBOX_TOKEN
npm install
npm run dev            # vite dev server
npm run build           # tsc -b && vite build
npm run lint             # eslint .
```

### Mobile (Flutter)

The Flutter app lives in `apps/mobile/` (`android/` is committed; there's
no `ios/` yet — run `flutter create .` there if you need it). Always run
Flutter commands from that folder, so generated output (`.dart_tool/`,
`build/`) lands in the right place:

```bash
cd apps/mobile
flutter pub get
flutter run
```

The API client in `apps/mobile/lib/core/api/api_client.dart` defaults to
`http://10.0.2.2:8000` (the Android emulator's alias for the host's
localhost) and hits gateway's `/health` endpoint.

Map tiles come from Mapbox when `MAPBOX_TOKEN` is defined, else from the
public OSM tile server (development only). Keep the token out of git: copy
`dart_defines.example.json` to `dart_defines.json` (gitignored), fill it in,
and run `flutter run --dart-define-from-file=dart_defines.json`.

### Python services (outside Docker)

Each service is independent — its own `requirements.txt`, run from the
service directory with `app/main.py` as the entrypoint, e.g.:

```bash
cd services/gateway
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

## Repo conventions

- Each Python service is independently deployable: its own
  `requirements.txt` and `Dockerfile`, entrypoint at `app/main.py`, exposing
  at minimum `GET /health`.
- `packages/shared-models` and `packages/shared-utils` are scaffolded but
  not yet installed into any service — intended to be pulled in via
  `pip install -e ../../packages/...` once there's real shared code to
  dedupe. Don't assume services currently import from them.
- No test suites, linters/CI configs, or business logic exist yet beyond
  what's described above — don't assume conventions here that aren't
  visible in the code.
