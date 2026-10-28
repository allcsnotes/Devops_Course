"""Course prices: PostgreSQL is the source of truth, Redis keeps a 5-minute copy."""

import psycopg
import redis

TTL_SECONDS = 300


class Catalog:
    def __init__(self, db: psycopg.Connection, cache: redis.Redis) -> None:
        self.db = db
        self.cache = cache

    def price(self, title: str) -> int | None:
        key = f"price:{title}"
        hit = self.cache.get(key)
        if hit is not None:
            return int(hit)
        row = self.db.execute("SELECT price FROM courses WHERE title = %s", (title,)).fetchone()
        if row is None:
            return None
        self.cache.set(key, row[0], ex=TTL_SECONDS)
        return int(row[0])
