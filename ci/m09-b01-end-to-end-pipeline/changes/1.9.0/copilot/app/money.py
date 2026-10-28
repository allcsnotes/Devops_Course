"""Prices for people: show(1299, "INR") -> "₹1,299"."""

SYMBOLS = {"INR": "₹", "EUR": "€", "USD": "$"}


def show(amount: int, currency: str) -> str:
    return f"{SYMBOLS.get(currency, currency + ' ')}{amount:,}"
