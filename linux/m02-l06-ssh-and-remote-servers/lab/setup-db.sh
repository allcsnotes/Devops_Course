#!/bin/bash
# db-01 only: a small allcsvideos database. The role password is a FAKE demo value. up.sh calls it.
set -e
for _ in $(seq 1 30); do systemctl is-active --quiet postgresql && break; sleep 1; done
sudo -u postgres psql -q <<'SQL'
CREATE ROLE allcs LOGIN PASSWORD 'demo-db-password';
CREATE DATABASE allcsvideos OWNER allcs;
SQL
sudo -u postgres psql -q -d allcsvideos <<'SQL'
SET ROLE allcs;
CREATE TABLE courses (id serial PRIMARY KEY, title text NOT NULL);
INSERT INTO courses (title) VALUES ('DSA'), ('System Design'), ('Spring Boot');
SQL
