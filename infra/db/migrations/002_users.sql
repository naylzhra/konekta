-- 002_users.sql
-- Users table for phone number + password auth (see
-- services/gateway/app/routers/auth.py, app/auth/user_store.py).
--
-- TODO: OTP verification of phone ownership is intentionally not
-- implemented yet -- phone_number here is just a login identifier, not a
-- verified-owned number.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TYPE user_role AS ENUM ('passenger', 'driver', 'admin');
CREATE TYPE user_status AS ENUM ('active', 'suspended');

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone_number VARCHAR(20) UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    role user_role NOT NULL,
    status user_status NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
