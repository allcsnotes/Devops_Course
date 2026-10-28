# Course Copilot - startup check (demo)
type Score = float      # new in Python 3.12

def top(scores: dict[str, Score]) -> str:
    return max(scores, key=scores.get)

print("Course Copilot ready. Top course:", top({"dsa": 4.9, "devops": 4.8}))
