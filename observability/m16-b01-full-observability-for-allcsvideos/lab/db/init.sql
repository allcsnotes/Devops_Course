-- catalog database for the M16-B01 lab (fake data): 24 courses with topics, 600,000 lesson transcript lines
CREATE ROLE app LOGIN PASSWORD 'demo-password-123';  -- fake lab password
CREATE TABLE courses (id int PRIMARY KEY, title text NOT NULL, topics text[] NOT NULL);
INSERT INTO courses VALUES
 (1,'DSA',ARRAY['arrays','graphs','dp','trees']), (2,'System Design',ARRAY['caching','sharding','queues']),
 (3,'Spring Boot',ARRAY['java','spring','jpa']), (4,'GenAI',ARRAY['llm','rag','embeddings']),
 (5,'DevOps',ARRAY['docker','kubernetes','terraform','linux','prometheus','grafana']);
INSERT INTO courses SELECT i, (ARRAY['DSA','System Design','Spring Boot','GenAI','DevOps'])[1 + i % 5] || ' · part ' || (i / 5), ARRAY[]::text[]
  FROM generate_series(6, 24) AS i;
-- lesson transcripts: no index for text search (version 1.1 of Course Copilot searches them with ILIKE)
CREATE TABLE lessons (id bigserial PRIMARY KEY, course_id int NOT NULL, transcript text NOT NULL);
INSERT INTO lessons (course_id, transcript)
SELECT 1 + g % 24, 'In this part we look at ' || (ARRAY['arrays','graphs','caching','queues','java','spring','llm','rag','docker',
  'kubernetes','terraform','linux','prometheus','grafana'])[1 + (g / 7) % 14] || ' with a worked example, step ' || g % 97 ||
  ', then a quiz about ' || md5(g::text) FROM generate_series(1, 600000) g;
GRANT SELECT ON courses, lessons TO app;
GRANT pg_monitor TO app;   -- read-only statistics for the Postgres exporter in Alloy
ANALYZE;
