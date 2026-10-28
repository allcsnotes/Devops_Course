"""load: about 10 requests per second to the catalog, forever (lab traffic generator)."""
import time
import urllib.error
import urllib.request

while True:
    try:
        urllib.request.urlopen("http://app:8080/api/courses", timeout=2).read()
    except (urllib.error.URLError, OSError):
        pass
    time.sleep(0.1)
