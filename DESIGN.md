# DESIGN.md — Passenger Trip: Booking + Live Tracking

Shared working design for the two passenger-trip workstreams. Both owners read and edit this file; changes to a **shared contract** (§5) need agreement from both before code depends on them. Note deviations in the PR.

## 0. Ownership

| Area | Owner | Where |
|---|---|---|
| Booking: trip plans, bookings, state machine, cancel, history, consent log | **Booking** | `services/gateway/app/bookings/`, `app/routers/bookings.py`, `infra/db/migrations/004_bookings.sql`, `apps/mobile/lib/features/booking/` |
| Home + Trips tab content | **Booking** | `features/booking/ui/` widgets, mounted by the passenger shell |
| WS hub routing (envelope, per-user delivery, topics) | **Booking** implements, both use | `services/gateway/app/websocket/manager.py` |
| Adaptive virtual stops: clustering, validation, candidate evaluation, feeder heuristic (§13) | **Booking** | `services/pooling-service/`, `services/stop-optimization-service/`; gateway orchestration planned (§13.6) |
| Live feeder position feed (Redis GEO → WS) | **Live tracking** | gateway feeder module + publisher (TBD by owner) |
| `FeederPositionProvider` (gateway) / `FeederPositionStream` (Flutter) | **Live tracking** | see §5.2, §5.4 |
| Device location `UserLocationProvider` (Flutter), location permission | **Live tracking** | see §5.3 |
| Passenger shell (`PassengerMain`, navbar, tab scaffold), Map tab, Profile tab | **Live tracking** | `features/passenger/`, `shared_widgets/` (currently only on `feat/user-live-tracking`) |
| Auth (sessions, roles, `require_role`) | merged (PR #1) — reuse, don't modify | `app/auth/`, `features/auth/` |
| Driver app UI | **unowned** — see §11. Live tracking owns only the on-duty location sharing in it | `features/driver/driver_home.dart` |
| Corridors/feeders, driver ↔ feeder binding, driver position reports | **Live tracking** | `app/feeders/`, `app/routers/feeders.py`, `005_feeders.sql`, `features/live_tracking/` |

Rule: need a change in the other side's area → propose it here, don't edit their files.

## 1. Product flow

**Passenger**
1. **Home** — "Ready to commute?" → destination input.
2. **Consent** — first trip only: location-processing consent recorded before any location is sent for planning (§8).
3. **Plan Trip** — origin (default: current location via `UserLocationProvider`) + destination → route options with fare estimate, time, nearest feeder, pooling hint.
4. **Booking** — confirm → system assigns a **pickup stop** + feeder.
5. **Walk to stop** — navigation/ETA to the stop (Map tab shows the feeder live).
6. **Pickup → ride → drop-off** — real-time status. Passenger taps "Saya sudah naik" when on board.
7. **Trips** — Active trip (live status) and History.

**Driver** — works per **stop**, not per passenger. Arrives at a pickup stop, picks up whoever is there, leaves. Does not confirm individual passengers. Arriving at a drop-off stop completes the trips of passengers on board who were going there.

Stops are `static` (fixed halte) or `virtual` (derived from observed demand and approved for operation, time-bound; §13). UI must label which.

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
- Booking: `features/booking/{domain,data,state,ui}/`; Home/Trips tab files in `features/passenger/tabs/` only mount booking widgets.
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
`PassengerMain` wraps its `KonektaTabScaffold` in `BookingScope(token:, child:)` (`features/booking/ui/booking_scope.dart`). The scope owns the per-login `BookingSession` (token, shared `ApiClient`, the app's single `WsClient`: connects it and disposes it on logout) and `BookingDependencies` (booking + history controllers shared by both tabs). Tabs stay `const` and read it with `BookingScope.of(context)`:
- `HomeTab` → `BookingHomeSection(controller:, locations:)`
- `TripsTab` → `TripsView(booking:, history:)`

Other tabs (Map) get the shared WS via `BookingScope.of(context).session.wsClient`; don't open a second connection. Origin/destination come from `TripLocations` (`features/booking/data/trip_locations.dart`): `StubTripLocations` (placeholder points, labelled in the UI) until `UserLocationProvider` (§5.3) and a place search exist.

### 5.6 Driver stop events (gateway REST) — owned by booking, called by the driver app (unowned) or simulator
`POST /driver/stops/{stop_id}/arrived` · `POST /driver/stops/{stop_id}/departed` — `require_role("driver")`, body `{feeder_id}`. Effects per §3. The live-tracking feed may also emit `arrived` automatically from geofencing later; same endpoint/effect.

### 5.7 Other consumed interfaces
- `StopAssigner` → pooling-service / stop-optimization-service: `assign_pickup_stop(request) -> Stop | None`. `StubStopAssigner` (`STOP_ASSIGNER=stub`) uses a small, clearly labelled placeholder stop list (no real halte data yet). Real implementation goes behind the same interface: the services compute candidates (§13), and assignment picks among *approved* stops only (§13.6).
- `RoutingClient` → OSRM-compatible via `OSRM_BASE_URL` (`osrm-mock` by default).
- Auth: `get_current_session` / `require_role` from `app/auth/dependencies.py`.

### 5.8 Live tracking REST (gateway) — owned by live tracking
- `GET /corridors` (public) → `{items: [{id, name, feeders: [{id, number, capacity, available}]}]}` — feeds the registration form.
- `POST /auth/register` takes `feeder_id` (required for `driver`, rejected for `passenger`); the user and the feeder claim are one transaction. Taken/unknown feeder → 409 `"Feeder not available"`. **Deviation from §0** (auth is "reuse, don't modify"): agreed with the product owner so drivers pick their feeder on the same form.
- `GET /feeders/me` (driver) → `{id, number, capacity, corridor_id, corridor_name}`; 404 `no_feeder_assigned`.
- `POST /feeders/me/position` (driver) `{lat, lng, heading?, accuracy_m?}` → `{feeder_id, updated_at}`; stores in Redis and publishes `feeder.position` to `feeder:{id}` (§5.1). Errors (`{"detail": {"code"}}`): 409 `no_feeder_assigned`, 422 `outside_service_area` / `inaccurate_position` (> 100 m), 429 `too_frequent` (< 1 s).
- `POST /feeders/me/offline` (driver) → 204; removes the feeder from the live set.
- One feeder per driver (`feeders.driver_id UNIQUE`); `feeder_id` = `feeders.id` (e.g. `K1-03`), also the WS topic suffix. Corridors/feeders in `005_feeders.sql` are **placeholders**.
- Redis: `feeders:geo` (GEO), `feeders:pos:<id>` (JSON `FeederPosition`, TTL 30 s = offline after 30 s without a report). No position history is persisted (§8). Service area = Bandung Raya, same box as `StubStopAssigner`.
- Driver app reports every ~5 s while on duty via a foreground service (notification shown); REST rather than a WS message so §5.1 (client → server types) stays unchanged.

### 5.9 Live tracking ↔ booking — what each side relies on
Changes by live tracking that touch booking, and what live tracking needs from booking. Booking owner: please confirm or push back here.

**Done by live tracking on `feat/user-live-tracking` (booking files untouched):**
- `PassengerMain` (shell) owns the passenger session: creates `BookingSession.create(token)` and one `BookingDependencies.create(session)`, calls `wsClient.connect()` and `booking.start()`, and disposes all of them. §5.5 says "whoever creates the session owns the WsClient", so this makes the shell that owner.
- The Map tab reads `BookingController` through `features/passenger/booking_active_trip.dart`. Fields it depends on (please don't rename without a note here): `current`, `Booking.isActive`, `Booking.feederId`, `Booking.pickupStop` (`name`, `location`), `Booking.status == BookingStatus.boarded`, and `pickupStopUpdate.location` (virtual stop moved).
- The Map tab subscribes to `feeder:<booking.feeder_id>` via `FeederPositionStream` while the booking is active, and unsubscribes when `feeder_id` changes or the booking ends.

**Requests to booking:**
1. **One `BookingController` per session:** `BookingHomeSection`/`TripsView` take the shell's `BookingDependencies` instead of building their own from the session (otherwise there are two controllers and two `GET /bookings/active` resyncs).
2. **Real feeder matching:** add `FEEDER_PROVIDER=redis` to `build_feeder_provider()`, returning `app.feeders.dependencies.get_position_provider()`. Until then bookings never get a `feeder_id` and the Map tab stays on "Mencari feeder...".
3. **Corridor ids:** `nearest(..., corridor_id)` filters strictly, but stub stops use `corridor_id="stub-corridor"` while real feeders are on `K1`/`K2`. Either give stub stops real corridor ids or pass `corridor_id=None` until real halte data exists.
4. **Driver stop events:** `POST /driver/stops/{id}/arrived|departed` can resolve the caller's feeder from `feeders.driver_id` instead of trusting `feeder_id` in the body (TODO in `routers/driver_stops.py`).

**Planned by live tracking, needs booking data:**
- **WS topic authorization** (TODO in `websocket/manager.py`): a passenger may subscribe only to `feeder:<id>` of their own active booking; a driver only to their own feeder; government to all. Live tracking will read the active booking's `feeder_id` from the bookings table (read-only) unless booking prefers to expose a helper for it.
- **`feeder.offline` WS event** when a driver ends duty or the position expires (today subscribers just stop receiving positions). New server → client type for §5.1.
- **Automatic `arrived`** from geofencing the feeder's position against the pickup stop (§5.6): same endpoint/effect as the manual event.

## 6. Booking API
REST (all require `Authorization: Bearer <token>`, passenger role unless noted):
- `POST /trip-plans` `{origin, destination, seats}` → `{plans: TripPlan[]}` (MVP returns one). Outside area / too short → 422 `no_route`. Routing down → 503 `routing_unavailable`. No consent → 403 `consent_required`.
- `POST /bookings` + `Idempotency-Key` → `Booking`. Same key + same body → same booking (200). Same key + different body → 409. Plan expired → 410. Active booking exists → 409 `active_booking_exists`. No consent → 403 `consent_required`.
- `POST /bookings/{id}/cancel`, body `{reason?}` · `POST /bookings/{id}/boarded` — idempotent by state (repeating returns the current booking), so no `Idempotency-Key`. Wrong state → 409 `invalid_transition`.
- `GET /bookings/active` (204 if none) · `GET /bookings?cursor=&limit=` → `{items, next_cursor}`
- `POST /consents` `{purpose, policy_version, granted}` · `GET /consents`
- Driver: §5.6.
Errors: `{"detail": {"code": "...", "message": "..."}}`.

## 7. UX states (each needs a UI)
Loading plans · outside corridor / no route · no supply (FAILED) · matching with timeout · virtual stop moved while walking · feeder delayed · location permission denied (from `UserLocationProvider`) · consent not given · offline/reconnecting · cancel confirm · NO_SHOW · expired plan (re-plan) · double-tap on confirm.

## 8. Privacy (UU PDP)
- Location requested only when needed, with stated purpose (live tracking owns the prompt).
- No raw location trails persisted on device. No coordinates or user ids in logs (gateway and Flutter).
- Consent recorded in `consent_log` (purpose `trip_location`, current `CONSENT_POLICY_VERSION`) before the first trip plan; gateway enforces on `/trip-plans` and `/bookings`, since plans already store origin/destination.
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
- **Live tracking:** §5.2–§5.4 implemented as specified (`UserLocation` adds optional `headingDeg`). Requests to booking and planned work that needs booking data: see §5.9.
- **Driver location consent:** drivers see a purpose rationale before the OS prompt, but nothing is recorded in `consent_log`; decide whether a `driver_tracking` purpose is needed (UU PDP).
- **Shell:** confirm the `BookingScope` wrap in `PassengerMain` (§5.5) with the shell owner (shell now owns the session on `feat/user-live-tracking`, see §5.9).
- **Real halte/corridor data** for `StopAssigner` and seed — corridor *geometry* is now also needed for §13.1.
- **Virtual stop thresholds (§13.8):** confirm service distance, max shift and max added travel time with Dishub Kota Bandung; tune ε/MinPts and hotspot thresholds on real demand.
- **Restricted-zone data (§13.5):** source for junctions / no-stopping zones (OSM extract or Dishub). Until then traffic safety passes by default and says so.
- **IoT feeder positions (§13.9):** ESP32 + GNSS devices report over Wi-Fi; needs device auth and a decision with live tracking on whether devices call `POST /feeders/me/position` or a device-specific endpoint.
- **Suspended users mid-trip:** auth's `require_not_suspended` reads session `active_trip_id`, which booking does not set. Agree with auth whether that matters for MVP.
- **Driver wait time** at a stop before departing: free choice for now; add a minimum if no-shows look unfair.

## 12. Repo facts
- Flutter is not installed in every dev environment; state in PRs whether `flutter analyze`/`flutter test` ran.
- `apps/mobile/android/` is committed (README says otherwise); manifest changes affect everyone.
- Passenger shell (`features/passenger/passenger_home.dart`, `tabs/`, `shared_widgets/konekta_*`) is on `dev`. Still don't branch from `feat/user-live-tracking`.

## 13. Adaptive virtual stops

Virtual stops come from observed demand, not from individual requests. A stop is proposed only when demand recurs, is evaluated against corridor, walking, safety and regulatory criteria, and is used for passengers only after operational approval. Following consultation with Dishub Kota Bandung, a proposal may **shift an existing stop** towards demand (within service-distance and travel-time limits) or add a new one. Candidates that aren't approved are still shown on the Government Mobility Intelligence Dashboard as recommendations.

```
trip_plans (window) --> pooling-service  POST /v1/demand-clusters
                         13.1 corridor + direction            -> drop trips no corridor serves
                         13.2 partition (corridor, direction, time slot) -> DBSCAN
                         13.3 hotspot validation              -> not valid: kept as history
                         13.4 weighted centroid               -> OSRM /nearest (validated only)
                    --> stop-optimization-service  POST /v1/stop-candidates/evaluate
                         13.5 coverage, walking, safety, regulation -> rank, resolve conflicts
                    --> gateway (planned, 13.6): store; government/operator approves -> stops (virtual)
```

Both services are **stateless**: the gateway (system of record) sends the data and stores the result. They receive no user ids: the gateway sends a per-run pseudonymous `requester_key` (salted hash) and request ids it can map back (§8). Each service keeps its own copy of the geometry helpers (`app/geo.py`) so it stays independently deployable.

### 13.1 Corridor identification — `pooling-service/app/corridors.py`
A trip belongs to the corridor whose catchment (`catchment_m`, default 800 m from the corridor path) holds **both** origin and destination and along which the trip progresses at least `min_corridor_progress_m` (300 m). Direction is `forward` when the destination projects further along the path than the origin, else `backward`. With several matches, the corridor with the smallest summed offset wins. Request **time** enters through the time-of-day slot (13.2); `requested_at` outside the run window is ignored.

### 13.2 Clustering — `pooling-service/app/clustering/dbscan.py`, `app/pipeline.py`
Requests are partitioned by `(corridor, direction, time slot)` — slot = `slot_minutes` (60) of WIB time of day — so only trips heading the same way at the same time of day can pool. Each partition runs DBSCAN with the **haversine** metric, so ε is in metres (`eps_m`, 150) with `min_pts` (4). The clustered point is the origin for pickup stops (`endpoint=pickup`) or the destination for drop-off stops (`endpoint=dropoff`). Noise is counted, not returned.

### 13.3 Demand hotspot validation — `pooling-service/app/validation.py`
| Check | Measure | Default |
|---|---|---|
| `unique_users` | distinct `requester_key` (people, not requests) | ≥ 5 |
| `spatial_concentration` | 80th-percentile distance of members to the centroid | ≤ 250 m |
| `temporal_consistency` | active days (WIB dates with demand), and active days / days in the window | ≥ 3 days and ≥ 0.3 |

All three pass → `validated` (a stop candidate). Otherwise the cluster comes back with `failed_checks` and is stored as historical demand for analysis.

### 13.4 Candidate point — `pooling-service/app/virtual_stop/centroid.py`, `app/osrm_client.py`
Weighted centroid of the cluster's points, each weighing `seats × 0.5^(age_days / recency_half_life_days)` (14 days) relative to the window end. Validated clusters are snapped onto the road with OSRM `/nearest` (`snapped_location`, `snap_distance_m`). OSRM failure → 503 `routing_unavailable` (no partial result). osrm-mock implements `/nearest` as identity (it has no road data).

### 13.5 Candidate evaluation — `stop-optimization-service/app/evaluation/evaluate.py`
Hard criteria (all must pass):

| Criterion | Rule | Default |
|---|---|---|
| `corridor_coverage` | distance from the stop to the corridor path | ≤ 100 m |
| `pedestrian_access` | demand-weighted share of cluster points whose estimated walk (straight line × 1.3) is within `max_walk_m` | ≥ 80 % within 400 m |
| `traffic_safety` | clearance from every restricted zone (junction, no-stopping, …) | ≥ 0 m (outside); passes with a note when no zones are supplied |
| `stop_spacing` (regulation) | distance to other stops on the corridor, excluding the one being shifted | ≥ 300 m |
| `operational_time` (regulation) | feeder out-and-back from the closest corridor point to the stop (OSRM driving) | ≤ 120 s |

A candidate within `max_shift_m` (500 m) of an existing stop on its corridor is `action=relocate_stop` (`relocates_stop_id`), else `new_stop`. Eligible candidates are scored `0.4·demand + 0.25·walk coverage + 0.2·(1 − added time / max) + 0.15·safety margin` (demand normalised to the batch maximum, safety margin capped at 50 m). Conflicts are resolved greedily by score: a candidate closer than the stop spacing to a better one, or shifting the same stop, becomes ineligible with the reason in `stop_spacing.detail`. Output: eligible candidates ranked first, then the rest, each with every check's value and threshold.

### 13.6 Lifecycle and approval — gateway (planned, next slice)
- Migration `006_virtual_stops.sql` (additive): corridor geometry (`corridors.path geography(LineString)`, `catchment_m`) with placeholder paths for K1/K2; `demand_clusters` (every cluster incl. non-validated, as history, linked to its `trip_plans`); `stop_candidates` (evaluation result + `status: proposed|approved|rejected|superseded`, `reviewed_by`, `reviewed_at`); `restricted_zones`.
- `POST /virtual-stops/runs` (`admin`/`government`): read `trip_plans` in the window → pooling-service → stop-optimization-service → store. Later a scheduled job.
- `GET /virtual-stops/candidates?status=` and `POST /virtual-stops/candidates/{id}/approve|reject` (`government`/`admin`) for the dashboard. Approve → insert a `virtual` stop (`valid_until` = review horizon, e.g. 30 days, re-validated by later runs); `relocate_stop` closes the shifted stop for new assignments instead of deleting it (bookings keep their snapshots, §2).
- `DbStopAssigner` (`STOP_ASSIGNER=db`): nearest approved stop (static or valid virtual) on the trip's corridor within `MAX_WALK_TO_STOP_M`. `StubStopAssigner` stays the default until approved stops exist; with `db`, no virtual stop is invented at the requested point any more.

### 13.7 Feeder operations heuristic — `stop-optimization-service/app/scoring/heuristic.py`
`POST /v1/feeder-stop-priorities` ranks stops with waiting passengers for one feeder: `0.5·active demand (normalised) − 0.3·min(detour / 600 s, 1) + 0.2·min(time since last served / 1800 s, 1)`. Demand density pulls the feeder to busy stops, detour cost keeps it on its run, and recency prevents starvation. Not called by the gateway yet (dispatch still uses `FeederPositionProvider.nearest`).

### 13.8 Parameters
All thresholds are request parameters with the defaults above (`PoolingParams`, `EvaluationParams`, `FeederHeuristicParams`), so runs can be tuned without a deploy. They are **starting values**, not validated: regulatory limits need confirmation with Dishub (§11), and clustering/hotspot thresholds need tuning on real demand.

### 13.9 Related, unchanged
- **Demand forecasting:** XGBoost on historical demand (`forecasting-service`, still a stub); its output will feed the dashboard and, later, slot-level demand for 13.2.
- **Feeder positions:** ESP32 + GPS/GNSS devices on feeders send coordinates over Wi-Fi; positions flow through live tracking (§5.8) into Redis GEO. Device auth/endpoint is an open question (§11).

### 13.10 Status
Implemented: 13.1–13.5 and 13.7 as service endpoints with unit tests (`services/pooling-service/tests`, `services/stop-optimization-service/tests`). Planned: 13.6. The gateway doesn't call either service yet; everything still missing is listed in 13.11.

### 13.11 Missing for further implementation
Ordered roughly by dependency. Owner is booking unless noted.

**A. Gateway slice (13.6) — needed before anything reaches passengers**
- [ ] `006_virtual_stops.sql`: `corridors.path geography(LineString,4326)` + `catchment_m` (placeholder K1/K2 paths, labelled as such); `virtual_stop_runs` (window, endpoint, params JSON, summary, started/finished, triggered_by) so every result is reproducible; `demand_clusters` (run id, cluster fields from §13.2–13.3, `validated`, `failed_checks`); `demand_cluster_members` (cluster id → `trip_plans.id`); `stop_candidates` (run id, cluster id, snapped location, evaluation JSON, `eligible`, `rank`, `score`, `action`, `relocates_stop_id`, `status`, `reviewed_by`, `reviewed_at`, `review_note`); `restricted_zones` (kind, location, radius_m, source).
- [ ] Stops lifecycle: a way to retire a shifted or expired stop for **new** assignments without deleting it (e.g. `stops.retired_at`), since bookings reference stops by id and keep snapshots (§2). Additive column; `stops_valid_until_matches_type` stays.
- [ ] Clients behind Protocols in `app/virtual_stops/clients.py` (`PoolingClient`, `StopEvaluationClient`) with timeouts and typed errors, `POOLING_URL` / `STOP_OPTIMIZATION_URL` config, and stub implementations for tests.
- [ ] Pseudonymisation before sending: `requester_key = HMAC(per-run random salt, user_id)`, salt never stored; request ids are `trip_plans.id`. No coordinates or ids in logs (§8).
- [ ] `POST /virtual-stops/runs` (`admin`/`government`), body `{window_start, window_end, endpoint, params?}`: read `trip_plans` in the window (origin, destination, created_at, seats from the booking if any, else 1), call pooling → evaluation, store run/clusters/candidates in one transaction. 503 if a service is down; nothing partial is stored.
- [ ] Candidate dedup across runs: a new candidate within `min_stop_spacing_m` of an open (`proposed`) candidate of the same corridor/direction/endpoint supersedes it (`status=superseded`) instead of piling up duplicates.
- [ ] `GET /virtual-stops/candidates?status=&corridor_id=` and `GET /virtual-stops/runs/{id}` for the dashboard; `POST /virtual-stops/candidates/{id}/approve|reject` with `review_note`. Approve: `new_stop` → insert `virtual` stop with `valid_until = now + VIRTUAL_STOP_REVIEW_DAYS` (30); `relocate_stop` → insert the new stop and retire the shifted one. Idempotent by state (repeat returns current), wrong state → 409 `invalid_transition`.
- [ ] `DbStopAssigner` (`STOP_ASSIGNER=db`): identify the trip's corridor + direction (same rule as 13.1, PostGIS `ST_Distance`/`ST_LineLocatePoint`), then the nearest non-retired, still-valid stop on that corridor within `MAX_WALK_TO_STOP_M`; none → 422 `no_route` (no stop is invented). Keep `stub` as default until approved stops exist. Also resolves §5.9 request 3 (stub corridor ids).
- [ ] Gateway tests (DB-backed, `TEST_DATABASE_URL`): run stores clusters/candidates, pseudonymisation (no user id leaves the gateway), approve/reject transitions and roles, dedup, `DbStopAssigner` picks approved stops only and respects retirement/expiry.

**B. Adaptivity over time**
- [ ] Scheduled runs (e.g. nightly over the last 28 days) in the gateway's background tasks, guarded so only one run executes at a time.
- [ ] Re-validation: an approved virtual stop whose cluster no longer validates in later runs is flagged for review before its `valid_until`, not silently extended. Approved stops still valid are extended on review.
- [ ] Decide whether a virtual stop is active only in the time slot(s) it was validated for (`active_slots`), or all day. Today `stops` has no notion of time of day; assignment would need it.
- [ ] Drop-off stops: run with `endpoint=dropoff` too, and use the results in `assign_dropoff_stop`.
- [ ] Notify affected passengers when a stop is relocated while they have an active booking at it (existing `stop.updated` event, §5.1).

**C. Data**
- [ ] Real corridor geometry and halte list from Dishub/operator (replaces placeholder paths and `STUB_STOPS`).
- [ ] Restricted zones: junctions from an OSM extract of Bandung, no-stopping/school zones from Dishub. Until loaded, `traffic_safety` passes with a note (13.5).
- [ ] Real OSRM with Bandung data (`OSRM_BASE_URL`); then switch the walking estimate from straight line × 1.3 to OSRM `foot` routes, and snapping becomes meaningful (osrm-mock's `/nearest` is identity).

**D. Services hardening**
- [ ] pooling-service runs DBSCAN inside an async handler, which blocks the event loop on large windows: move clustering to a worker thread (`run_in_threadpool`) and measure with ~50k requests.
- [ ] Service-to-service auth: pooling (:8001) and stop-optimization (:8002) have no auth and are published on host ports by compose. In deployment keep them on the private network only, or add a shared internal token.
- [ ] Parameter tuning on real demand (ε, MinPts, hotspot thresholds) and Dishub confirmation of regulatory limits (§11, 13.8); record the agreed values as defaults.
- [ ] `geo.py` exists in both services (intentional copy); keep them identical when changing either.

**E. Feeder operations and forecasting**
- [ ] Wire the feeder heuristic (13.7) into dispatch: needs active demand per stop (non-terminal bookings), detour per feeder (OSRM from the feeder's position, §5.2) and last-served time (from driver `departed` events, §5.6, which need persisting).
- [ ] Forecasting (XGBoost, `forecasting-service`): features from `demand_clusters` history per corridor/direction/slot; output to the dashboard and as expected demand for 13.2. Not started.
- [ ] IoT feeder positions (ESP32 + GNSS over Wi-Fi): device identity and auth, endpoint decision with live tracking (§11).

**F. Other owners**
- [ ] Dashboard (React, not booking): candidate list/map with per-criterion results, approve/reject, run history. Needs the API in A.
- [ ] Mobile: nothing new required for passengers beyond the existing static/virtual label; approved virtual stops arrive as normal stops.

**G. Housekeeping**
- [ ] Retention: `demand_clusters`/members and `virtual_stop_runs` follow the backend retention job (§8); members link to `trip_plans`, so deleting plans must cascade or null.
- [ ] Update `AGENTS.md` (still says not to implement logic in pooling/stop-optimization) and the service rows in `README.md`.
