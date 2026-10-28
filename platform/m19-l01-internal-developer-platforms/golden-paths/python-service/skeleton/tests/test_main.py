import unittest

from app.main import SERVICE, handle


class TestHandle(unittest.TestCase):
    def test_health(self):
        self.assertEqual(handle("/healthz"), (200, {"status": "ok"}))

    def test_root_names_the_service(self):
        status, body = handle("/")
        self.assertEqual(status, 200)
        self.assertEqual(body["service"], SERVICE)

    def test_unknown_path(self):
        self.assertEqual(handle("/nope")[0], 404)


if __name__ == "__main__":
    unittest.main()
