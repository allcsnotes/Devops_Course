# SEALED (game master only). Scenario 1: a bad release reaches production
HYPOTHESIS="a bad release (1.1 fails 1 in 10 course lists) pages within 3 minutes, is rolled back within 6, and costs under 5% of the course-list budget"
inject()   { ../deploy.sh 1.1 ci; }
rollback() { if docker compose -f ../compose.yaml exec -T api1 python -c 'import urllib.request;print(urllib.request.urlopen("http://127.0.0.1:8080/healthz").read().decode())' | grep -q ' 1.1'; then
               ../deploy.sh 1.0 gm; else echo "nothing to do: the responders already rolled back"; fi; }
