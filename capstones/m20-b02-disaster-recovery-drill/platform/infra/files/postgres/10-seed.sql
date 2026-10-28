-- allcsvideos catalog (first boot only): 40 courses, 300,000 fake enrollments (example.com addresses only)
CREATE USER allcs PASSWORD 'FAKE-lab-allcs-pass-202';      -- FAKE lab password; the app reads it from Vault
CREATE TABLE courses (id int PRIMARY KEY, title text NOT NULL);
CREATE TABLE enrollments (
  id         bigserial PRIMARY KEY,
  student    text NOT NULL,
  course_id  int  NOT NULL REFERENCES courses(id),
  created_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO courses
SELECT i, (ARRAY['Linux Basics','Docker Deep Dive','Kubernetes in Production','System Design','Spring Boot','Generative AI','Data Structures','Terraform'])[1 + (i - 1) % 8]
          || CASE WHEN i > 8 THEN ' ' || (1 + (i - 1) / 8) ELSE '' END
FROM generate_series(1, 40) i;
INSERT INTO enrollments (student, course_id, created_at)
SELECT 'student' || lpad((i % 999999)::text, 6, '0') || '@example.com', 1 + i % 40, now() - interval '30 days' + i * interval '8 seconds'
FROM generate_series(1, 300000) i;
GRANT SELECT ON courses TO allcs;
GRANT SELECT, INSERT ON enrollments TO allcs;
GRANT USAGE ON SEQUENCE enrollments_id_seq TO allcs;
