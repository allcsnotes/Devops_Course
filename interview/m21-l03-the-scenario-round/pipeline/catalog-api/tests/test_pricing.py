import unittest
from pricing import inr, discounted

class Pricing(unittest.TestCase):
    def test_grouping(self):
        self.assertEqual(inr(12999900), "Rs 1,29,999")
        self.assertEqual(inr(49900), "Rs 499")
    def test_discount(self):
        self.assertEqual(discounted(100000, 20), 80000)
        with self.assertRaises(ValueError):
            discounted(100000, 95)
