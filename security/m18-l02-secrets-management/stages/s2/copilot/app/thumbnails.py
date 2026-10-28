"""Upload course thumbnails to S3 (lab stand-in: it only prepares the request, nothing is sent)."""

import requests

# FAKE demo key, staged for this lesson. Not a real credential.
AWS_ACCESS_KEY_ID = "__FAKE_AWS_KEY_ID__"
AWS_SECRET_ACCESS_KEY = "__FAKE_AWS_SECRET__"
BUCKET_URL = "https://allcsvideos-media.s3.amazonaws.com"


def upload_request(name: str, data: bytes) -> requests.PreparedRequest:
    auth = (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
    return requests.Request("PUT", f"{BUCKET_URL}/thumbnails/{name}", data=data, auth=auth).prepare()
