# Registers the IoT GPS device mounted in a feeder and prints its API token
# (shown once; only its hash is stored). Re-running for the same feeder
# replaces its device and token.
#
#   python -m app.cli.create_device --device-id esp32-k1-01 --feeder K1-01
#
# Inside docker-compose:
#   docker compose -f infra/docker/docker-compose.yml exec gateway \
#       python -m app.cli.create_device --device-id esp32-k1-01 --feeder K1-01
import argparse
import asyncio
import re
import sys

from app.db import close_pool, get_pool
from app.feeders.device_tokens import generate_token, hash_token
from app.feeders.repository import upsert_device


async def _create(device_id: str, feeder_id: str) -> None:
    try:
        pool = await get_pool()
        async with pool.acquire() as conn:
            if await conn.fetchval("SELECT 1 FROM feeders WHERE id = $1", feeder_id) is None:
                sys.exit(f"Unknown feeder {feeder_id}")
            token = generate_token()
            await upsert_device(conn, device_id, feeder_id, hash_token(token))
        print(f"Registered device {device_id} for feeder {feeder_id}")
        print(f"API token (store it on the device; it is not shown again): {token}")
    finally:
        await close_pool()


def main() -> None:
    parser = argparse.ArgumentParser(description="Register an IoT GPS device for a feeder")
    parser.add_argument("--device-id", required=True, help="Letters, digits, - or _, up to 64 chars")
    parser.add_argument("--feeder", required=True, help="Feeder id, e.g. K1-01")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", args.device_id):
        sys.exit("Invalid device id")
    asyncio.run(_create(args.device_id, args.feeder))


if __name__ == "__main__":
    main()
