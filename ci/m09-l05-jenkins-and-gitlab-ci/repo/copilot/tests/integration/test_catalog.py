"""Integration tests: a real PostgreSQL and a real Redis (CI starts them as service containers)."""

import os

import psycopg
import pytest
import redis

from app.catalog import Catalog

pytestmark = pytest.mark.integration


@pytest.fixture
def cache():
    r = redis.Redis.from_url(os.environ["REDIS_URL"])
    r.flushdb()
    return r


@pytest.fixture
def db():
    with psycopg.connect(os.environ["DATABASE_URL"]) as conn:
        yield conn


def test_price_comes_from_postgres(db, cache):
    assert Catalog(db, cache).price("DevOps") == 499


def test_price_is_cached_in_redis(db, cache):
    Catalog(db, cache).price("DevOps")
    assert cache.get("price:DevOps") == b"499"
    assert 0 < cache.ttl("price:DevOps") <= 300


def test_unknown_course(db, cache):
    assert Catalog(db, cache).price("Cooking") is None
