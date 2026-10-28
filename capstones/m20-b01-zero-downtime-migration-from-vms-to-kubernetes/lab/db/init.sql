-- catalog database for the migration lab (fake data only)
CREATE USER allcs PASSWORD 'demo-password-123';           -- FAKE lab password
CREATE TABLE courses (id serial PRIMARY KEY, title text NOT NULL);
INSERT INTO courses (title) VALUES ('Linux for DevOps'), ('Docker in Depth'), ('Kubernetes in Production'),
  ('System Design Basics'), ('Data Structures in C++'), ('GenAI Foundations');
CREATE TABLE progress (id bigserial PRIMARY KEY, student text NOT NULL, lesson int NOT NULL, run text NOT NULL,
  at timestamptz NOT NULL DEFAULT now());
GRANT SELECT ON courses TO allcs;
GRANT SELECT, INSERT ON progress TO allcs;
GRANT USAGE ON SEQUENCE progress_id_seq TO allcs;
