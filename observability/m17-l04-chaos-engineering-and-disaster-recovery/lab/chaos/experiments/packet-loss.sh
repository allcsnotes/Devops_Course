# Drop 30% of the packets api2 sends (tc netem, needs the NET_ADMIN capability)
HYPOTHESIS="with 30% packet loss on api2, retries keep errors under 0.1% and p99 under 250 ms"
DURATION=30
inject()   { docker compose -f ../compose.yaml exec -u 0 api2 tc qdisc add dev eth0 root netem loss 30% && echo "netem loss 30% on api2"; }
rollback() { docker compose -f ../compose.yaml exec -u 0 api2 tc qdisc del dev eth0 root && echo "netem removed from api2"; }
