# Deploying the backend to Azure (Azure for Students)

The backend (gateway, pooling, stop-optimization, osrm-mock, Postgres/PostGIS,
Redis) runs on one Linux VM with Docker Compose. Caddy in front gives
HTTPS. Only ports 80/443 are public. The mobile app and dashboard aren't
deployed here.

## 1. Activate Azure for Students

Go to azure.microsoft.com/free/students → **Start free** → sign in with
your campus email. No credit card needed. You get credit (check the current
amount) plus some free-tier VM hours. Track spending under **Cost
Management** in the portal.

## 2. Make an SSH key (on your laptop, once)

```powershell
ssh-keygen -t ed25519
# press Enter for all prompts
Get-Content $HOME\.ssh\id_ed25519.pub
```

Copy the line it prints (`ssh-ed25519 AAAA...`). That's your **public**
key, and it's safe to paste into Azure. Never share `id_ed25519`, the file
without `.pub`.

## 3. Create the VM

Portal → **Virtual machines** → **Create** → **Azure virtual machine**:

| Field                 | Value                                                    |
|-----------------------|----------------------------------------------------------|
| Subscription          | Azure for Students                                       |
| Resource group        | Create new: `konekta`                                    |
| VM name               | `konekta`                                                |
| Region                | **East Asia** (see note below)                           |
| Image                 | Ubuntu Server 24.04 LTS — x64 Gen2                       |
| Size                  | **Standard_B2ats_v2** (free-tier eligible, x64, 2 vCPU / 1 GiB) |

Student subscriptions can't use every size in every region
("NotAvailableForSubscription"). To see what yours allows, open **Cloud
Shell** (`>_` in the portal's top bar) → Bash:

```bash
az vm list-skus --resource-type virtualMachines --size Standard_B -o table | grep -E "B1s |B2ats_v2 "
```

Rows ending in `None` are allowed. Ignore regions you can't pick in the portal
(`SoutheastAsia3`, `EastUSSTG`, …), which are internal Azure regions. Avoid ARM
sizes (`B2pts_v2`): the Postgres image is x64-only.
| Authentication        | SSH public key → username `azureuser` → paste the key from step 2 |
| Inbound ports         | Allow **SSH (22), HTTP (80), HTTPS (443)**               |

**Disks** tab: keep **Premium SSD** (the free tier covers a 64 GB "P6"
disk; check the price on the Review page), tick **Delete with VM**.
**Management** tab: make sure **auto-shutdown is off**. Then **Review +
create** → **Create**.

When it's done: VM → **Overview** → click **DNS name: Not configured** →
set a label (e.g. `konekta`) → **Save**. You now have a free domain like
`konekta.eastasia.cloudapp.azure.com`.

## 4. Connect

```powershell
ssh azureuser@<public-ip-or-dns-name>
```

Type `yes` the first time. Everything below runs **on the VM**.

## 5. Prepare the VM

```bash
# 1 GB RAM is tight. Add 2 GB of swap so builds and Postgres don't get killed.
sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Docker
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker azureuser
exit   # log out and ssh back in so the docker group applies
```

## 6. Get the code and start it

```bash
git clone -b <branch> https://github.com/<you>/konekta.git && cd konekta
```

Private repo? GitHub will ask for a username and a **personal access
token**, not your password (GitHub → Settings → Developer settings →
Personal access tokens → fine-grained, read-only access to this repo).

```bash
cp infra/azure/.env.example infra/azure/.env
openssl rand -hex 24          # copy this, it's your POSTGRES_PASSWORD
nano infra/azure/.env         # set API_DOMAIN + POSTGRES_PASSWORD; Ctrl+O, Enter, Ctrl+X

echo "alias kc='docker compose --env-file infra/azure/.env -f infra/docker/docker-compose.yml -f infra/azure/docker-compose.prod.yml'" >> ~/.bashrc
source ~/.bashrc

kc up -d --build              # first build takes a few minutes
kc ps                         # everything should be "running" / "healthy"
```

Migrations in `infra/db/migrations` run automatically on this first start.

## 7. Check it

From your laptop:

```powershell
curl https://<API_DOMAIN>/health
```

If HTTPS fails, `kc logs caddy` usually says why. Common causes are port
80/443 not being open in the VM's **Networking** tab, or `API_DOMAIN` not
matching the DNS name.

Create the government account:

```bash
kc exec gateway python -m app.cli.create_user --phone +62... --role government
```

## 8. Point the clients at it

- **Mobile**: `flutter run --dart-define=API_BASE_URL=https://<API_DOMAIN>`
- **Dashboard** (local `npm run dev`): `VITE_GATEWAY_URL=https://<API_DOMAIN>`
  in `apps/dashboard/.env`.

## Day to day

```bash
ssh azureuser@<API_DOMAIN>
cd konekta
git pull && kc up -d --build     # deploy new code
kc logs -f gateway               # watch logs
```

New migration files **don't** run automatically on an existing database.
Apply one by hand:

```bash
kc exec -T postgres psql -U konekta konekta < infra/db/migrations/0XX_name.sql
```

Backup (copy the file off the VM afterwards, e.g. with `scp`):

```bash
kc exec -T postgres pg_dump -U konekta konekta | gzip > ~/konekta-$(date +%F).sql.gz
```

## Demand forecasting (XGBoost)

`forecasting-service` runs as one-off jobs under the `forecasting` profile,
never as a long-lived container (see `services/forecasting-service/README.md`).
First time, after `git pull`:

```bash
kc exec -T postgres psql -U konekta konekta < infra/db/migrations/014_demand_forecasts.sql
kc up -d --build gateway                                    # /dashboard/demand-forecast
kc --profile forecasting build forecasting-service
kc --profile forecasting run --rm forecasting-service python -m app.training.train
kc --profile forecasting run --rm forecasting-service python -m app.jobs.predict
```

Keep forecasts fresh with cron (`crontab -e`; the `kc` alias isn't available
there): predict daily, retrain weekly so new trial bookings are picked up.

```
30 0 * * * cd ~/konekta && docker compose --env-file infra/azure/.env -f infra/docker/docker-compose.yml -f infra/azure/docker-compose.prod.yml --profile forecasting run --rm forecasting-service python -m app.jobs.predict >> ~/forecast.log 2>&1
0 0 * * 1 cd ~/konekta && docker compose --env-file infra/azure/.env -f infra/docker/docker-compose.yml -f infra/azure/docker-compose.prod.yml --profile forecasting run --rm forecasting-service python -m app.training.train >> ~/forecast.log 2>&1
```

After changing forecasting code: `git pull`, then rebuild with
`kc --profile forecasting build forecasting-service` and rerun train + predict.

## Cost notes

- **Stopping the VM from the portal** (Stop → "deallocated") stops compute
  charges. The disk still costs a little. Data is kept.
- **Deleting the `konekta` resource group** removes everything, including
  the database, for good.
- If 1 GB turns out too slow, resize the VM (VM → **Size**) to B1ms (2 GB)
  or B2s (4 GB). Those spend credit, so check the monthly estimate first.
