# KONEKTA Ops Dashboard

React + Vite dashboard for the `government` role — Mapbox GL (map) +
Recharts (charts). Only `government` accounts can log in; any other role is
rejected and logged back out.

## Running

```bash
docker compose -f infra/docker/docker-compose.yml up --build
```

Then, in another terminal:

```bash
cd apps/dashboard
cp .env.example .env   # set VITE_MAPBOX_TOKEN
npm install
npm run dev            # http://localhost:5173
```

| Variable            | Default                 | Notes                              |
|---------------------|-------------------------|------------------------------------|
| `VITE_MAPBOX_TOKEN` | —                       | Required, otherwise the map is blank |
| `VITE_GATEWAY_URL`  | `http://localhost:8000` | Gateway base URL                   |

Keep the dev server on port `5173`: the gateway only allows
`http://localhost:5173` via `CORS_ORIGINS`. If vite falls back to another
port (e.g. `5174` because `5173` is taken), browser requests to the gateway
will be blocked — free the port or add the new origin to `CORS_ORIGINS`.

Other scripts:

```bash
npm run build   # tsc -b && vite build
npm run lint    # eslint .
```

## Creating a government account

Government accounts can't self-register via `POST /auth/register`, and no
admin UI is needed — they're created directly in the database with the
gateway's CLI (`services/gateway/app/cli/create_user.py`). With the stack
running, from the repo root:

```bash
docker compose -f infra/docker/docker-compose.yml exec gateway python -m app.cli.create_user --phone +6281234567890 --role government
```

It prompts for a password twice (min. 8 characters, input is hidden). Log in
to the dashboard with that phone number and password.

### If it fails with `invalid input value for enum user_role: "government"`

The `government` role is added by
`infra/db/migrations/003_add_government_role.sql`. Postgres only runs the
migrations folder when its data volume is first created, so a
`postgres_data` volume created before that migration existed won't have the
role. Apply it manually, then rerun `create_user`:

```bash
docker compose -f infra/docker/docker-compose.yml exec -T postgres psql -U konekta -d konekta -f - < infra/db/migrations/003_add_government_role.sql
```
