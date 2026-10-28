-- allcsvideos catalog for the game day: 40 courses (fake data)
CREATE TABLE courses (id int PRIMARY KEY, title text NOT NULL);
INSERT INTO courses
SELECT i, (ARRAY['Linux Basics','Docker Deep Dive','Kubernetes in Production','System Design','Spring Boot','Generative AI','Data Structures','Terraform'])[1 + (i - 1) % 8]
          || CASE WHEN i > 8 THEN ' ' || (1 + (i - 1) / 8) ELSE '' END
FROM generate_series(1, 40) i;
