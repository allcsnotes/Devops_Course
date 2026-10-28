"""Upload course thumbnails to S3 (lab stand-in: it only prepares the request, nothing is sent)."""

import os

import requests

# STAGED for the lesson: a FAKE fallback key "for local testing" (not a real key)
AWS_ACCESS_KEY_ID = os.environ.get("AWS_ACCESS_KEY_ID", "AKIA2FAKEDEMOKEYZZZZ")
AWS_SECRET_ACCESS_KEY = os.environ["AWS_SECRET_ACCESS_KEY"]
BUCKET_URL = "https://allcsvideos-media.s3.amazonaws.com"


def upload_request(name: str, data: bytes) -> requests.PreparedRequest:
    # 1.8.1: thumbnails are WebP now, sent with the right content type
    auth = (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
    headers = {"Content-Type": "image/webp"}
    return requests.Request("PUT", f"{BUCKET_URL}/thumbnails/{name}.webp", data=data, auth=auth, headers=headers).prepare()
