# Kill one of the two API replicas (like a crashed machine) while the students keep coming
HYPOTHESIS="with api1 killed, the load balancer keeps errors under 0.1% and p99 under 250 ms"
DURATION=30
inject()   { docker compose -f ../compose.yaml kill api1; }
rollback() { docker compose -f ../compose.yaml start api1; }
