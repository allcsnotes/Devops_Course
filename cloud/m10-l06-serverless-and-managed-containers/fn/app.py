import json, os
COURSES = ["DSA", "System Design", "Spring Boot", "GenAI", "DevOps"]
def handler(event, context):
    q = (event or {}).get("q", "").lower()
    hits = [c for c in COURSES if q in c.lower()]
    print(json.dumps({"q": q, "hits": len(hits)}))
    return {"statusCode": 200, "body": json.dumps({"courses": hits, "region": os.environ["AWS_REGION"]})}
