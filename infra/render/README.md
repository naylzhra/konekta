# Deploying the backend to Render (free tier)

`render.yaml` at the repo root is a Render Blueprint. It creates:

| Render resource             | Type         | From                                  |
|-----------------------------|--------------|---------------------------------------|
| `konekta-gateway`           | Web Service  | `services/gateway`                    |
| `konekta-pooling`           | Web Service  | `services/pooling-service`            |
| `konekta-stop-optimization` | Web Service  | `services/stop-optimization-service`  |
| `konekta-osrm-mock`         | Web Service  | `services/osrm-mock`                  |
| `konekta-db`                | Postgres     | PostGIS enabled by migration 001      |
| `konekta-redis`             | Key Value    | sessions + live feeder positions      |

The mobile app and dashboard aren't deployed. Render only builds the
folders listed above, and `buildFilter` keeps pushes that only touch
`apps/` from redeploying anything. `forecasting-service` is left out because
nothing calls it yet. Add it to `render.yaml` once the gateway uses it.

## 1. Create everything

1. Push `render.yaml` to the branch you want to deploy (normally `main`).
2. In Render: **New → Blueprint** → connect the GitHub repo → pick the
   branch → **Apply**.
3. Once the services are live, open each one and check its URL. If any
   isn't `https://<service-name>.onrender.com`, fix the matching `*_URL`
   env var on `konekta-gateway` / `konekta-pooling` /
   `konekta-stop-optimization`.

## 2. Run the migrations

Render's free plan can't run them on deploy, so run them from your
machine. Copy **konekta-db → Connect → External Database URL**, then:

```bash
pip install asyncpg
python infra/render/migrate.py "postgresql://konekta:...@...singapore-postgres.render.com/konekta"
```

Re-run it whenever a new file lands in `infra/db/migrations/`. It skips
the ones already applied.

## 3. Check it

```bash
curl https://konekta-gateway.onrender.com/health
```

Create the government account (run from `services/gateway`, against the
same External Database URL):

```powershell
cd services/gateway
pip install -r requirements.txt
$env:DATABASE_URL = "<External Database URL>"
python -m app.cli.create_user --phone +62... --role government
```

## 4. Point the clients at it

- **Mobile**: `flutter run --dart-define=API_BASE_URL=https://konekta-gateway.onrender.com`
- **Dashboard** (local `npm run dev`): `VITE_GATEWAY_URL=https://konekta-gateway.onrender.com`
  in `apps/dashboard/.env`. `CORS_ORIGINS` already allows `http://localhost:5173`.

## Free-tier limits to keep in mind

- **The database expires.** Free Postgres is deleted 30 days after
  creation (plus a 14-day grace period to upgrade), and it has no
  backups. To keep data longer, move to a free Neon or Supabase Postgres
  (both support PostGIS). Set the gateway's `DATABASE_URL` to it and run
  `migrate.py` against it.
- **Services sleep** after 15 minutes without requests, and waking takes
  about a minute. The gateway calls pooling, which calls osrm-mock, so the
  first request after idling can time out (the gateway client waits 30 s).
  Retry once everything is awake. Hitting `/health` on each service warms
  them up.
- **750 free instance hours per month** are shared by the whole workspace.
  Four services that stay awake would use them up in about a week, after
  which they're suspended until the month ends. Check usage under
  **Billing**.
- **Key Value (Redis) isn't persisted** on the free plan. A restart logs
  everyone out and clears live feeder positions.
