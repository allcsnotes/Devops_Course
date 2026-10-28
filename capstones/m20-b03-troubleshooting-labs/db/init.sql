-- allcs database on db-01 (lab). The app role's password is a FAKE lab value, set by lab.sh.
CREATE TABLE courses (id serial PRIMARY KEY, title text NOT NULL);
INSERT INTO courses (title) VALUES ('DSA'), ('System Design'), ('DevOps'), ('GenAI'), ('Spring Boot');
