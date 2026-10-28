# Nightly course report (lab job with a staged bug): it opens one database connection per course and never closes them.
import os, time, psycopg2
DB = dict(host=os.environ["DB_HOST"], dbname=os.environ["DB_NAME"], user=os.environ["DB_USER"],
          password=os.environ["DB_PASSWORD"], connect_timeout=3, application_name="nightly-report")
held = []
for course in range(1, 41):
    try:
        held.append(psycopg2.connect(**DB))          # BUG: never closed
    except psycopg2.Error as e:
        print(f"course {course}: {str(e).strip()}", flush=True)
        break
print(f"holding {len(held)} connections", flush=True)
while True:
    time.sleep(60)
