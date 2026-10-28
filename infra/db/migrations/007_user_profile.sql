-- Optional public name for passenger and driver profiles.
ALTER TABLE users ADD COLUMN IF NOT EXISTS display_name VARCHAR(80);
