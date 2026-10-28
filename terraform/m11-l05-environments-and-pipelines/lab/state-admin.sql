-- state-admin.sql: run once by the state admin (PostgreSQL superuser tfstate) in the lab state database.
-- One schema per environment, and three lab roles with FAKE passwords:
--   tf_plan     read-only on both states (pull-request and main-branch plans)
--   tf_staging  read/write on the staging state only
--   tf_prod     read/write on the prod state only (its secret lives only in infra-production)
CREATE SEQUENCE IF NOT EXISTS public.global_states_id_seq AS bigint;
CREATE ROLE tf_plan LOGIN PASSWORD 'fake-lab-pass-plan';
CREATE ROLE tf_staging LOGIN PASSWORD 'fake-lab-pass-staging';
CREATE ROLE tf_prod LOGIN PASSWORD 'fake-lab-pass-prod';
GRANT USAGE, SELECT, UPDATE ON SEQUENCE public.global_states_id_seq TO tf_staging, tf_prod;
CREATE SCHEMA staging; CREATE SCHEMA prod;
CREATE TABLE staging.states (id bigint NOT NULL DEFAULT nextval('public.global_states_id_seq') PRIMARY KEY, name text UNIQUE, data text);
CREATE TABLE prod.states (id bigint NOT NULL DEFAULT nextval('public.global_states_id_seq') PRIMARY KEY, name text UNIQUE, data text);
CREATE UNIQUE INDEX states_by_name ON staging.states (name);
CREATE UNIQUE INDEX states_by_name ON prod.states (name);
GRANT USAGE ON SCHEMA staging, prod TO tf_plan;
GRANT SELECT ON staging.states, prod.states TO tf_plan;
GRANT USAGE ON SCHEMA staging TO tf_staging; GRANT SELECT, INSERT, UPDATE, DELETE ON staging.states TO tf_staging;
GRANT USAGE ON SCHEMA prod TO tf_prod; GRANT SELECT, INSERT, UPDATE, DELETE ON prod.states TO tf_prod;
