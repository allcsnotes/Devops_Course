"""Apply SQL migration files to DATABASE_URL (for CI jobs whose image has no psql)."""

import os
import sys

import psycopg

with psycopg.connect(os.environ["DATABASE_URL"], autocommit=True) as conn:
    for path in sys.argv[1:]:
        with open(path) as f:
            conn.execute(f.read().encode())
        print(f"applied {path}")
