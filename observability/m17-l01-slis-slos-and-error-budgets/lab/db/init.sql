-- catalog database for the M17-L01 lab: 24 courses
CREATE ROLE app LOGIN PASSWORD 'demo-password-123';  -- fake lab password
CREATE TABLE courses (id int PRIMARY KEY, title text NOT NULL);
INSERT INTO courses SELECT i, (ARRAY['DSA','System Design','Spring Boot','GenAI','DevOps','Linux','Docker','Kubernetes'])[1 + (i - 1) % 8]
  || ' · part ' || (1 + (i - 1) / 8) FROM generate_series(1, 24) AS i;
GRANT SELECT ON courses TO app;
