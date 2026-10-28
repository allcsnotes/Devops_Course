"""Upload course thumbnails to S3 (lab stand-in: it only prepares the request, nothing is sent)."""

import os

import requests

# the key comes from the environment at run time (a secrets manager in lesson 2), never from the code
AWS_ACCESS_KEY_ID = os.environ["AWS_ACCESS_KEY_ID"]
AWS_SECRET_ACCESS_KEY = os.environ["AWS_SECRET_ACCESS_KEY"]
BUCKET_URL = "https://allcsvideos-media.s3.amazonaws.com"


def upload_request(name: str, data: bytes) -> requests.PreparedRequest:
    auth = (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
    return requests.Request("PUT", f"{BUCKET_URL}/thumbnails/{name}", data=data, auth=auth).prepare()
