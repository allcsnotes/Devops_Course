-- staged on purpose: a schema migration that holds its lock on courses for 30 seconds
BEGIN;
ALTER TABLE courses ADD COLUMN level text;   -- takes an ACCESS EXCLUSIVE lock on courses
SELECT pg_sleep(30);                         -- stands in for a slow backfill, inside the same transaction
COMMIT;
