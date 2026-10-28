# "integration" tests, staged slow on purpose: each one waits 4 s for a fake database to be ready,
# like a real test that starts a database container and sleeps instead of polling.
import time, unittest
from pricing import inr, discounted

class ApiC(unittest.TestCase):
    def setUp(self):
        time.sleep(4)          # staged: "wait for the database"
    def test_course_price_c(self):
        self.assertTrue(inr(discounted(299900, 10)).startswith("Rs "))
    def test_free_course_c(self):
        self.assertEqual(inr(discounted(0, 0)), "Rs 0")
