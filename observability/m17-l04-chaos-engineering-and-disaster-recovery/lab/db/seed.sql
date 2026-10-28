-- allcsvideos catalog: 40 courses and 1,000,000 fake enrollments (example.com addresses only)
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
SELECT 'student' || lpad((i % 999999)::text, 6, '0') || '@example.com', 1 + i % 40, now() - interval '30 days' + i * interval '2.5 seconds'
FROM generate_series(1, 1000000) i;
