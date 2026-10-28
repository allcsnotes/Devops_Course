-- catalog database for the lab: 24 courses and 2,000,000 fake enrollments (no real students)
CREATE TABLE courses (id int PRIMARY KEY, title text NOT NULL, price_inr int NOT NULL);
INSERT INTO courses SELECT i, 'Course ' || i, 499 + (i % 5) * 500 FROM generate_series(101, 124) i;
CREATE TABLE enrollments (id bigserial PRIMARY KEY, student_id int NOT NULL, course_id int NOT NULL, enrolled_at timestamptz NOT NULL);
INSERT INTO enrollments (student_id, course_id, enrolled_at)
  SELECT (random() * 200000)::int, 101 + (random() * 23)::int, now() - random() * interval '400 days'
  FROM generate_series(1, 2000000);
CREATE INDEX enrollments_student ON enrollments (student_id);
ANALYZE;
