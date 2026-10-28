from app.money import show


def test_rupees():
    assert show(499, "INR") == "₹499"


def test_thousands_separator():
    assert show(1299, "INR") == "₹1,299"
