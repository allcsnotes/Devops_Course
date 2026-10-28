#!/usr/bin/env bash
# The bot at 192.0.2.66: "start" makes it POST to the public login page once a second, "stop" ends it.
case "${1:-}" in
  start) docker exec -d bot sh -c 'while true; do curl -s -o /dev/null --max-time 2 -X POST -d "user=admin&password=guess" http://203.0.113.1/login; sleep 1; done'
         echo "bot started" ;;
  stop)  docker exec bot pkill -f 'while true' 2>/dev/null; docker exec bot pkill sh 2>/dev/null; echo "bot stopped" ;;
  *)     echo "usage: bash lab/bot.sh start|stop" >&2; exit 1 ;;
esac
