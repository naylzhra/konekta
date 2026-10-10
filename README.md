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
  mobile/        Flutter app — single codebase, passenger + driver roles
  dashboard/     React + Vite ops dashboard — Mapbox GL (map) + Recharts (charts)

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

The `apps/mobile` folder currently only contains the Dart source
(`pubspec.yaml` + `lib/`) — no platform (`android/`/`ios/`) folders yet.
Generate them once, then run as usual:

```bash
cd apps/mobile
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

## Known risks and open items

Things that can bite you locally or that still need an owner/decision.
Design-level open questions live in `DESIGN.md` §11.

**Local dev**
- **Gateway crashes on a fresh database.** In `docker-compose.yml`,
  `gateway` uses `depends_on` without `condition: service_healthy` and has
  no restart policy, so on first boot it connects before Postgres finishes
  init and exits. Workaround: `docker compose -f infra/docker/docker-compose.yml start gateway`
  once Postgres is healthy.
- **Migrations only run on a fresh volume** (`docker-entrypoint-initdb.d`).
  After pulling a new migration (e.g. `004_bookings.sql`), either reset
  with `docker compose -f infra/docker/docker-compose.yml down -v` (wipes
  local data) or apply the file with `psql`.
- **Gateway tests must run in the gateway image (Python 3.11).** Pinned
  `pydantic==2.9.2` does not install on newer host Pythons (e.g. 3.14).
  DB-backed tests are skipped unless `TEST_DATABASE_URL` is set; they drop
  and re-create a database whose name must end in `_test` (your dev
  database is never touched). With the compose stack up:
  ```bash
  docker run --rm --network docker_default \
    -v "$PWD/services/gateway:/app" -v "$PWD/infra/db/migrations:/migrations:ro" \
    -e TEST_DATABASE_URL=postgresql://konekta:konekta@postgres:5432/konekta_test \
    -e MIGRATIONS_DIR=/migrations -w /app docker-gateway:latest \
    sh -c "pip install -q -r requirements-dev.txt && python -m pytest -q"
  ```
  (Git Bash on Windows: prefix with `MSYS_NO_PATHCONV=1`.)
- **Session token appears in gateway access logs.** The WS endpoint takes
  the token as `?token=` (existing auth/hub contract), and uvicorn's access
  log prints the full URL. Needs a decision with auth: filter the access
  log, or move the token out of the URL.
- **WS hub is in-process.** `send_to_user()`/`publish()` only reach clients
  connected to the same gateway process; more than one worker/replica
  needs Redis pub/sub behind the hub.
- **Flutter checks are not run everywhere.** Not every dev environment has
  Flutter installed; PRs should state whether `flutter analyze` /
  `flutter test` actually ran.
- `apps/mobile/android/` is committed, contrary to the Flutter section
  above; changes to `AndroidManifest.xml` affect everyone.

**Booking / passenger trip**
- **Boarding depends on the driver "arrived" signal.** A booking only moves
  CONFIRMED → FEEDER_ARRIVING when the driver reports arriving at the
  pickup stop (or the feeder comes within range). If neither happens, the
  passenger cannot mark themselves boarded. Fine with the demo simulator;
  a real driver app must send "arrived" reliably.
- **Driver app UI has no owner.** `driver_home.dart` is a placeholder;
  driver stop events come from a simulator for the demo
  (`BOOKING_SIMULATOR=1 docker compose ... up gateway`).
- **Driver ↔ feeder binding is trusted.** `POST /driver/stops/{id}/arrived|departed`
  takes `feeder_id` from the request body; any driver account can act for
  any feeder until a driver/feeder assignment exists.
- **Fare is a placeholder tariff** (`app/bookings/config.py`: base + per-km,
  rounded up to Rp500) until the real fare policy is decided.
- **No real halte/corridor data.** Stop assignment uses clearly labelled
  placeholder stops until real Bandung halte coordinates are provided.
- **Passenger shell is not on `main`.** The tab shell/navbar lives on
  `feat/user-live-tracking`; booking screens mount in `main`'s
  `passenger_home.dart` until it is merged.
- **Location encryption at rest is volume-level, not column-level.**
  Column `pgcrypto` would break PostGIS spatial indexes; revisit if the
  deployment plan requires column encryption (UU PDP).
- **Suspended users mid-trip.** Auth's `require_not_suspended` reads the
  session's `active_trip_id`, which booking does not set (the DB is the
  source of truth for active bookings). Needs agreement with auth.
