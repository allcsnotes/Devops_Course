-- staged on purpose: a schema migration that holds its lock on courses for 3 minutes
BEGIN;
ALTER TABLE courses ADD COLUMN level text;   -- takes an ACCESS EXCLUSIVE lock on courses
SELECT pg_sleep(180);                        -- stands in for a slow backfill, inside the same transaction
ROLLBACK;                                    -- lab: undo, so the next run starts the same
