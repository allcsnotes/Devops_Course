# "The site is down" - runbook

Work outside-in, one step at a time. Write down what you ran and what you saw. Change one thing, then test again.

Replace `allcsvideos.test` / `10.0.56.10` with your own name and address.

| # | Question | Run | Healthy | If it fails |
|---|----------|-----|---------|-------------|
| 1 | Is it just me? | Ask a second vantage point (a colleague, another network, an uptime check). Test other pages and names: `curl -sS -o /dev/null -w '%{http_code}\n' https://allcsvideos.test/` | Everyone sees the same thing | Only some users or names fail: suspect DNS, a CDN or one route. Only you: your network, VPN or local cache |
| 2 | Does DNS give the right address? | `dig +short www.allcsvideos.test` and `dig +short @<authoritative-server> www.allcsvideos.test` | The address you expect, the same from both | Wrong or missing address: fix the record, bump the serial, mind the TTL. Prove it with `curl --resolve name:443:<right-ip>` |
| 3 | Can I reach the host? | `ping -c 4 <ip>` · `mtr -n --report -c 10 <ip>` · `traceroute -n <ip>` | 0% loss, steady latency | Loss or latency from one hop onward: that hop or link. No reply at all can just mean ICMP is blocked: go on to step 4 |
| 4 | Is the port open? | `nc -zv -w 5 <ip> 443` · on the server: `sudo ss -tlnp` | succeeded | **refused** (instant): nothing listens, start or fix the service. **timed out**: a firewall or security group drops it. Find where with `tcpdump -n -i any port 443` on each box, and `traceroute -T -p 443` |
| 5 | Is TLS valid? | `openssl s_client -connect <name>:443 -servername <name> </dev/null 2>/dev/null \| openssl x509 -noout -subject -dates -ext subjectAltName` · `curl -v` | Verify return code: 0, dates valid, the name in the SAN list | Expired, wrong name, missing chain: deploy the right certificate, `nginx -t`, reload. `curl -k` only to confirm, never in scripts |
| 6 | What does HTTP say, and how fast? | `curl -s -o /dev/null -w @curl-format.txt https://<name>/path` | 2xx/3xx, fast | **502**: the proxy can't reach its upstream. **504**: the upstream was too slow (proxy_read_timeout). Slow: compare connect / appconnect (network, TLS) with starttransfer (backend) |
| 7 | What do the logs say? | `sudo tail /var/log/nginx/error.log` · access log with `$request_time $upstream_response_time` · `journalctl -u <service> --since "10 min ago"` | No errors at the time of the failure | The error line names the upstream, the reason and the time. Follow it to the next box |

## curl-format.txt

```
   namelookup:  %{time_namelookup}s\n
      connect:  %{time_connect}s\n
   appconnect:  %{time_appconnect}s\n
  pretransfer:  %{time_pretransfer}s\n
starttransfer:  %{time_starttransfer}s\n
        total:  %{time_total}s\n
         code:  %{http_code}\n
```

All times are seconds from the start of the request. connect minus namelookup = TCP handshake (one round trip). appconnect minus connect = TLS handshake. starttransfer minus pretransfer = one more round trip plus the time the server spends on the request.

## Rules

- One change at a time, and test after each one.
- Test from where your users are, not only from the server.
- ICMP blocked is not the same as host down.
- tcpdump on the wrong interface shows nothing: start with `-i any`.
- Write it down: commands, outputs, times. That becomes the incident timeline.
