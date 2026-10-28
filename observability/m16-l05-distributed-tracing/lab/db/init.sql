-- catalog database for the M16-L05 lab (fake data)
CREATE TABLE courses (id int PRIMARY KEY, title text NOT NULL, price_inr int NOT NULL);
INSERT INTO courses VALUES
 (101,'Linux from zero',499),(102,'Docker in depth',499),(103,'Kubernetes in production',799),
 (104,'Terraform on AWS',699),(105,'Observability',599),(106,'System Design',999),
 (107,'Spring Boot',799),(108,'Generative AI',899),(109,'DSA in C++',699),
 (110,'Git and GitHub',299),(111,'Networking basics',399),(112,'Python for Ops',499);
-- 2,000,000 enrollments, no index on student_id (the staged problem)
CREATE TABLE enrollments (id bigserial PRIMARY KEY, student_id int NOT NULL, course_id int NOT NULL, enrolled_at timestamptz NOT NULL);
INSERT INTO enrollments (student_id, course_id, enrolled_at)
SELECT (random()*200000)::int, 101 + (g % 12), now() - (g % 900) * interval '1 day'
FROM generate_series(1, 2000000) g;
INSERT INTO enrollments (student_id, course_id, enrolled_at) VALUES (3181,103,now()),(3181,105,now());
ANALYZE;
