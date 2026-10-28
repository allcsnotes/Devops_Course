# Add 100 ms to every packet api2 sends (tc netem, needs the NET_ADMIN capability)
HYPOTHESIS="with 100 ms extra network delay on api2, p99 stays under 250 ms"
DURATION=30
inject()   { docker compose -f ../compose.yaml exec -u 0 api2 tc qdisc add dev eth0 root netem delay 100ms && echo "netem delay 100ms on api2"; }
rollback() { docker compose -f ../compose.yaml exec -u 0 api2 tc qdisc del dev eth0 root && echo "netem removed from api2"; }
