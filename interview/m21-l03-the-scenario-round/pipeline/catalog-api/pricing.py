"""Prices for the course list (pure functions, so they are easy to test)."""

def inr(paise: int) -> str:
    """12999900 paise -> 'Rs 1,29,999' (Indian digit grouping)."""
    r = paise // 100; s = str(r)
    if len(s) > 3:
        head, tail = s[:-3], s[-3:]
        parts = []
        while len(head) > 2:
            parts.insert(0, head[-2:]); head = head[:-2]
        if head: parts.insert(0, head)
        s = ",".join(parts) + "," + tail
    return "Rs " + s

def discounted(paise: int, percent: int) -> int:
    if not 0 <= percent <= 90:
        raise ValueError("discount must be 0-90 percent")
    return paise * (100 - percent) // 100
