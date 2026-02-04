-- Required PostgreSQL extensions for ISO 28258
-- Run BEFORE applying the schema release file
--
-- Usage (for downstream projects):
--   psql -d your_db -f migrations/setup/extensions.sql
--   psql -d your_db -f releases/iso28258_v1.9.sql
--
-- Or in .gmrc afterReset:
--   ["setup/extensions.sql", "setup/iso28258_v1.9.sql"]

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
