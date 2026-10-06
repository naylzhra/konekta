# DESIGN.md — Passenger Trip: Booking + Live Tracking

Shared working design for the two passenger-trip workstreams. Both owners read and edit this file; changes to a **shared contract** (§5) need agreement from both before code depends on them. Note deviations in the PR.

## 0. Ownership

| Area | Owner | Where |
|---|---|---|
| Booking: trip plans, bookings, state machine, cancel, history, consent log | **Booking** | `services/gateway/app/bookings/`, `app/routers/bookings.py`, `infra/db/migrations/004_bookings.sql`, `apps/mobile/lib/features/booking/` |
| Home + Trips tab content | **Booking** | `features/booking/ui/` widgets, mounted by the passenger shell |
| WS hub routing (envelope, per-user delivery, topics) | **Booking** implements, both use | `services/gateway/app/websocket/manager.py` |
| Live feeder position feed (Redis GEO → WS) | **Live tracking** | gateway feeder module + publisher (TBD by owner) |
| `FeederPositionProvider` (gateway) / `FeederPositionStream` (Flutter) | **Live tracking** | see §5.2, §5.4 |
| Device location `UserLocationProvider` (Flutter), location permission | **Live tracking** | see §5.3 |
| Passenger shell (`PassengerMain`, navbar, tab scaffold), Map tab, Profile tab | **Live tracking** | `features/passenger/`, `shared_widgets/` (currently only on `feat/user-live-tracking`) |
| Auth (sessions, roles, `require_role`) | merged (PR #1) — reuse, don't modify | `app/auth/`, `features/auth/` |
| Driver app UI | **unowned** — see §11 | `features/driver/driver_home.dart` (placeholder) |

Rule: need a change in the other side's area → propose it here, don't edit their files.

## 1. Product flow

**Passenger**
1. **Home** — "Ready to commute?" → destination input.
2. **Plan Trip** — origin (default: current location via `UserLocationProvider`) + destination → route options with fare estimate, time, nearest feeder, pooling hint.
3. **Consent** — first booking only: location-processing consent recorded (§8).
4. **Booking** — confirm → system assigns a **pickup stop** + feeder.
5. **Walk to stop** — navigation/ETA to the stop (Map tab shows the feeder live).
6. **Pickup → ride → drop-off** — real-time status. Passenger taps "Saya sudah naik" when on board.
7. **Trips** — Active trip (live status) and History.

**Driver** — works per **stop**, not per passenger. Arrives at a pickup stop, picks up whoever is there, leaves. Does not confirm individual passengers. Arriving at a drop-off stop completes the trips of passengers on board who were going there.

Stops are `static` (fixed halte) or `virtual` (computed, time-bound). UI must label which.

## 2. Domain model
- `Stop { id, type: static|virtual, location, name, corridor_id, valid_until? }`
- `TripPlan { id, user_id, origin, destination, legs[], fare_estimate, eta_minutes, pickup_stop, dropoff_stop, corridor_id, expires_at }` — stored server-side so fare/expiry can't be forged by the client.
- `Booking { id, user_id, trip_plan_id, status, pickup_stop (snapshot), dropoff_stop (snapshot), feeder_id?, fare_estimate (snapshot), cancellation_fee, eta_to_pickup_s?, seats, idempotency_key, cancel_reason?, version, created_at, updated_at }`
- `Feeder { id, corridor_id, position, occupancy, heading, updated_at }` — owned by live tracking; booking reads it only through `FeederPositionProvider`.
- `ConsentLog { id, user_id, purpose, policy_version, granted, created_at }` — append-only.

Pickup/dropoff stop and fare are snapshotted into the booking at confirmation; later stop changes never rewrite history. Corridors have no table yet; `corridor_id` is free text until one exists.

## 3. Booking state machine (server authoritative)
```
REQUESTED ─► MATCHING ─► CONFIRMED ─► FEEDER_ARRIVING ─► BOARDED ─► COMPLETED
    │            │           │              │
    └────────────┴───────────┴──────────────┴──► CANCELLED      (passenger, until BOARDED)
MATCHING ─► FAILED                (no supply / no stop in range)
CONFIRMED | FEEDER_ARRIVING ─► NO_SHOW   (driver departs pickup stop, passenger not boarded)
REQUESTED | MATCHING | CONFIRMED ─► EXPIRED   (timeout)
```
| Transition | Triggered by |
|---|---|
| REQUESTED → MATCHING → CONFIRMED / FAILED | gateway (StopAssigner + FeederPositionProvider) |
| CONFIRMED → FEEDER_ARRIVING | gateway: assigned feeder within `ARRIVING_RADIUS_M` of pickup stop, or driver `arrived` at that stop |
| FEEDER_ARRIVING → BOARDED | passenger "Saya sudah naik" |
| CONFIRMED/FEEDER_ARRIVING → NO_SHOW | driver `departed` the pickup stop while the booking isn't BOARDED |
| BOARDED → COMPLETED | driver `arrived` at the booking's drop-off stop |
| → CANCELLED | passenger (fee = `CANCELLATION_PENALTY`, 0 for MVP) |
| → EXPIRED | gateway sweep (`MATCHING_TIMEOUT_S`) |

- Terminal: COMPLETED, CANCELLED, FAILED, NO_SHOW, EXPIRED.
- Every transition bumps `version`; invalid transition returns a typed error (HTTP 409 `invalid_transition`), never a silent no-op.
- One active (non-terminal) booking per user, enforced by a DB partial unique index and mirrored in UI.
- Flutter mirrors the transition table for rendering/validation only; on conflict the server wins and the client reconciles.
- Until a driver app exists, driver stop events come from a `BookingSimulator` behind `BOOKING_SIMULATOR=1` (demo only).

## 4. Where code goes

**Gateway** (`services/gateway/app/`) — existing layout: routers in `app/routers/`, asyncpg via `app/db.py`, `redis.asyncio`, config via `os.getenv` at point of use.
- Booking: `bookings/{models,state_machine,service,repository,events,clients,config,simulator}.py`, `routers/bookings.py`, `routers/consents.py`, `routers/driver_stops.py`. Tests in `services/gateway/tests/`, dev deps in `requirements-dev.txt`.
- Live tracking: feeder module of the owner's choosing; implements `FeederPositionProvider` and publishes `feeder.position` through the hub (§5.1).

**DB:** additive `00N_*.sql`, never edit earlier files. `004_bookings.sql` (booking): `stops`, `trip_plans`, `bookings`, `consent_log`. Live tracking adds its own migration if it persists anything. Migrations only run on a **fresh** Postgres volume (`docker-entrypoint-initdb.d`) — after pulling a new migration, `docker compose ... down -v` or apply it with `psql`.

**Mobile** (`apps/mobile/lib/`), state management = plain `StatefulWidget` / `ChangeNotifier` (Flutter SDK). No third-party state library.
- Booking: `features/booking/{domain,data,state,ui}/`.
- Live tracking: `features/passenger/` shell + Map/Profile tabs, location + feeder stream under `core/` or its own feature folder.
- Shared: `core/api/api_client.dart` (one HTTP client — extend, don't duplicate), `core/websocket/ws_client.dart` (one WS connection per app session, see §5.1), `core/strings/` (all Bahasa Indonesia strings), `core/theme/konekta_theme.dart`.

## 5. Shared contracts

### 5.1 WebSocket hub — `/ws/{client_id}?token=<session token>`
One connection per app session, shared by booking and live tracking. Server indexes connections by the session's `user_id` (from the token, not `client_id`).

Envelope (both directions):
```json
{ "type": "booking.updated", "payload": { ... } }
```
Server → client:
| type | owner | payload | delivery |
|---|---|---|---|
| `booking.updated` | booking | full `Booking` snapshot (incl. `version`) | to the booking's user |
| `stop.updated` | booking | `{stop_id, location, valid_until}` | to users with an active booking at that stop |
| `feeder.position` | live tracking | `{feeder_id, lat, lng, heading, occupancy, updated_at}` | to subscribers of `feeder:{id}` |
| `error` | hub | `{code, message}` | to the sender |

Client → server: `{"type":"subscribe","payload":{"topic":"feeder:<id>"}}`, `{"type":"unsubscribe",...}`, `{"type":"ping"}`.

Gateway hub API (in `manager.py`): `send_to_user(user_id, type, payload)`, `publish(topic, type, payload)`, subscription handling. Each workstream only calls these; neither adds a second WS endpoint.

Client rules: reconnect with backoff → resubscribe topics → `GET /bookings/active` to resync; drop `booking.updated` whose `version` ≤ current.

### 5.2 `FeederPositionProvider` (gateway, Python) — implemented by live tracking
```python
class FeederPositionProvider(Protocol):
    async def get_last_known(self, feeder_id: str) -> FeederPosition | None: ...
    async def nearest(self, lat: float, lng: float, radius_m: float, corridor_id: str | None = None, limit: int = 5) -> list[FeederPosition]: ...
```
`FeederPosition { feeder_id, lat, lng, heading, occupancy, capacity, corridor_id, updated_at }`. Booking uses `nearest` for matching and `get_last_known` for ETA. Redis key layout is the live-tracking owner's choice. Booking ships a `StubFeederPositionProvider` (`FEEDER_PROVIDER=stub`) until the real one lands.

### 5.3 `UserLocationProvider` (Flutter) — implemented by live tracking
```dart
abstract class UserLocationProvider {
  Future<LocationPermissionState> permissionState();
  Future<LocationPermissionState> requestPermission();   // shows purpose rationale first
  Future<UserLocation?> getCurrent();                    // null if denied/unavailable
  Stream<UserLocation> stream();
}
// UserLocation { double lat, lng; double? accuracyM; DateTime at; }
// LocationPermissionState { granted, denied, deniedForever, serviceDisabled }
```
Single permission flow for the whole app; booking never requests location itself. Booking uses a mock until it lands.

### 5.4 `FeederPositionStream` (Flutter) — implemented by live tracking
`Stream<FeederPosition> subscribe(String feederId)`, `FeederPosition? lastKnown(String feederId)`, over the shared WS (§5.1). Booking uses it for "feeder arriving" ETA on the Active Trip screen.

### 5.5 Passenger shell ↔ tab content
Booking exposes widgets: `BookingHomeSection({required BookingSession session})` and `TripsView({required BookingSession session})`. `BookingSession` carries the auth token and the shared `ApiClient`/`WsClient`.
Request to shell owner: `PassengerMain` passes the session into `HomeTab`/`TripsTab` (today the tabs are `const` and receive no token). Until the shell is on `main`, booking mounts its widgets in `main`'s `passenger_home.dart`.

### 5.6 Driver stop events (gateway REST) — owned by booking, called by the driver app (unowned) or simulator
`POST /driver/stops/{stop_id}/arrived` · `POST /driver/stops/{stop_id}/departed` — `require_role("driver")`, body `{feeder_id}`. Effects per §3. The live-tracking feed may also emit `arrived` automatically from geofencing later; same endpoint/effect.

### 5.7 Other consumed interfaces
- `StopAssigner` → pooling-service / stop-optimization-service: `assign_pickup_stop(request) -> Stop | None`. `StubStopAssigner` (`STOP_ASSIGNER=stub`) uses a small, clearly labelled placeholder stop list (no real halte data yet). Real HTTP client goes behind the same interface; don't implement logic inside those services.
- `RoutingClient` → OSRM-compatible via `OSRM_BASE_URL` (`osrm-mock` by default).
- Auth: `get_current_session` / `require_role` from `app/auth/dependencies.py`.

## 6. Booking API
REST (all require `Authorization: Bearer <token>`, passenger role unless noted):
- `POST /trip-plans` → `TripPlan[]`
- `POST /bookings` + `Idempotency-Key` → `Booking`. Same key + same body → same booking (200). Same key + different body → 409. Plan expired → 410. Active booking exists → 409 `active_booking_exists`. No consent → 403 `consent_required`.
- `POST /bookings/{id}/cancel` + `Idempotency-Key`, body `{reason}`
- `POST /bookings/{id}/boarded` + `Idempotency-Key`
- `GET /bookings/active` (204 if none) · `GET /bookings?cursor=`
- `POST /consents` `{purpose, policy_version, granted}` · `GET /consents`
- Driver: §5.6.
Errors: `{"detail": {"code": "...", "message": "..."}}`.

## 7. UX states (each needs a UI)
Loading plans · outside corridor / no route · no supply (FAILED) · matching with timeout · virtual stop moved while walking · feeder delayed · location permission denied (from `UserLocationProvider`) · consent not given · offline/reconnecting · cancel confirm · NO_SHOW · expired plan (re-plan) · double-tap on confirm.

## 8. Privacy (UU PDP)
- Location requested only when needed, with stated purpose (live tracking owns the prompt).
- No raw location trails persisted on device. No coordinates or user ids in logs (gateway and Flutter).
- Consent recorded in `consent_log` (purpose `trip_location`) before the first booking; gateway enforces.
- Location columns use `geography(Point,4326)` for spatial queries; at-rest encryption is at the storage/volume level per the deployment plan (column-level `pgcrypto` would break spatial indexes). Revisit if the deployment plan requires column encryption.
- Retention/deletion job is backend-wide (not yet owned); clients must handle deleted/expired records gracefully.

## 9. Testing
- Gateway (`pytest`, `requirements-dev.txt`): state machine (all valid/invalid transitions), idempotency, one-active-booking constraint, consent gate, router tests with stub providers; WS hub routing (per-user delivery, topic subscribe).
- Mobile (`flutter test`): transition table, repository against mock API, WS simulation (duplicate, out-of-order, reconnect).
- Demo path: plan → confirm → matching → confirmed → arriving → boarded → completed, plus cancel, no-supply and no-show.

## 10. UI/visual
Tokens live in `lib/core/theme/konekta_theme.dart` (`AppColors`, `AppSpacing`, `AppRadius`, `AppTextStyles`) — reuse, don't hardcode. User-facing strings in Bahasa Indonesia, centralized under `lib/core/strings/`.

## 11. Decisions and open questions

Resolved:
1. WS hub: one endpoint (`/ws/{client_id}`); booking owner implements the envelope + per-user index + topics (§5.1).
2. Device location: live-tracking owner (§5.3).
3. One active booking per user for MVP. DB is the source of truth; booking does not write auth's session `active_trip_id`.
4. Fare: server-computed only.
5. Cancellation: `CANCELLATION_PENALTY` constant, 0 for MVP.
6. Roles: fixed per account at registration, routed by `features/auth/role_router.dart`; no in-app role switch.
7. Driver works per stop: arrive → pick up → depart; no per-passenger confirmation. Passenger confirms boarding; not boarded when driver departs → NO_SHOW.
8. Consent log: booking owner, in `004_bookings.sql`.

Open:
- **Driver app UI owner** (`driver_home.dart`): calls §5.6. Simulator covers the demo until then.
- **Live tracking:** confirm §5.2–§5.4 signatures and `feeder.position` payload.
- **Shell:** when `PassengerMain`/navbar lands on `main`, and the §5.5 session-passing change.
- **Real halte/corridor data** for `StopAssigner` and seed.
- **Suspended users mid-trip:** auth's `require_not_suspended` reads session `active_trip_id`, which booking does not set. Agree with auth whether that matters for MVP.
- **Driver wait time** at a stop before departing: free choice for now; add a minimum if no-shows look unfair.

## 12. Repo facts
- Flutter is not installed in every dev environment; state in PRs whether `flutter analyze`/`flutter test` ran.
- `apps/mobile/android/` is committed (README says otherwise); manifest changes affect everyone.
- Passenger shell exists only on `feat/user-live-tracking`; don't branch from it.
