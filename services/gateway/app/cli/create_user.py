# Provisions accounts that can't self-register through POST /auth/register
# (government accounts for the ops dashboard, admin accounts).
#
#   python -m app.cli.create_user --phone +6281234567890 --role government
#
# Inside docker-compose:
#   docker compose -f infra/docker/docker-compose.yml exec gateway \
#       python -m app.cli.create_user --phone +6281234567890 --role government
import argparse
import asyncio
import getpass
import sys

from app.auth import user_store
from app.auth.passwords import hash_password
from app.db import close_pool


async def _create(phone_number: str, password: str, role: str) -> None:
    try:
        if await user_store.get_user_by_phone(phone_number) is not None:
            sys.exit(f"Phone number {phone_number} is already registered")
        user = await user_store.create_user(phone_number, hash_password(password), role)
        print(f"Created {user['role']} user {user['id']} ({user['phone_number']})")
    finally:
        await close_pool()


def main() -> None:
    parser = argparse.ArgumentParser(description="Create a government or admin account")
    parser.add_argument("--phone", required=True, help="Phone number incl. country code, e.g. +6281234567890")
    parser.add_argument("--role", required=True, choices=["government", "admin"])
    args = parser.parse_args()

    password = getpass.getpass("Password: ")
    if password != getpass.getpass("Confirm password: "):
        sys.exit("Passwords do not match")
    if len(password) < 8:
        sys.exit("Password must be at least 8 characters")

    asyncio.run(_create(args.phone, password, args.role))


if __name__ == "__main__":
    main()
