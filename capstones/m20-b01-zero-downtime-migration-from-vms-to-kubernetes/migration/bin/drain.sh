#!/bin/bash
# drain.sh: is anything still talking to the VMs? Requests in flight (the app's own gauge) and open TCP connections
# on port 8080, per server.
for h in web-01:11 web-02:12; do
  ip=10.0.201.${h#*:}
  if m=$(curl -sf --max-time 2 $ip:8080/metrics); then f=$(echo "$m" | awk '/^http_requests_in_flight /{print int($2)}'); else f="- (API stopped)"; fi
  c=$(ssh -q asha@$ip "ss -Htn state established '( sport = :8080 )' | wc -l")
  echo "${h%%:*}  in flight: $f  open connections: $c"
done
