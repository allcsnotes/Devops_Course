-- 001: the course catalogue (fake demo data)
CREATE TABLE IF NOT EXISTS courses (
  id    serial PRIMARY KEY,
  title text NOT NULL UNIQUE,
  price integer NOT NULL
);
INSERT INTO courses (title, price) VALUES
  ('DevOps', 499), ('System Design', 499), ('Spring Boot', 499)
ON CONFLICT (title) DO NOTHING;
