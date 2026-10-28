-- catalog database for the M16-L01 lab: 24 courses, and 2,000,000 course views (no index on views: the popular sort scans it)
CREATE ROLE app LOGIN PASSWORD 'demo-password-123';  -- fake lab password
CREATE TABLE courses (id int PRIMARY KEY, title text NOT NULL);
INSERT INTO courses SELECT i, (ARRAY['DSA','System Design','Spring Boot','GenAI','DevOps','Linux','Docker','Kubernetes'])[1 + (i - 1) % 8]
  || ' · part ' || (1 + (i - 1) / 8) FROM generate_series(1, 24) AS i;
CREATE TABLE views (course_id int NOT NULL, viewed_at timestamptz NOT NULL);
INSERT INTO views SELECT 1 + (random() * 23)::int, now() - random() * interval '90 days' FROM generate_series(1, 2000000);
GRANT SELECT ON courses, views TO app;
ANALYZE;
