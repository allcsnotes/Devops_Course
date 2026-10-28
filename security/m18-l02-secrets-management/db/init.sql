-- lab catalog database (allcsvideos): a few rows for the read-only dynamic user to read
CREATE TABLE courses (id serial PRIMARY KEY, title text NOT NULL, price_inr int NOT NULL);
INSERT INTO courses (title, price_inr) VALUES ('DevOps: From Linux to Kubernetes', 3499), ('System Design', 2999), ('Generative AI', 3299);
-- the account Vault uses to create and drop short-lived users (its FAKE password is rotated by Vault right after setup)
CREATE ROLE vault_admin WITH LOGIN CREATEROLE PASSWORD 'FAKE-lab-vault-admin-123';
GRANT SELECT ON ALL TABLES IN SCHEMA public TO vault_admin WITH GRANT OPTION;
