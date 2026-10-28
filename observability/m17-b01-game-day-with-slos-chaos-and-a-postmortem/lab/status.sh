#!/bin/bash
# status.sh STATUS COMPONENT STATE MESSAGE: post an update to the (lab) status page
jq -n --arg s "$1" --arg c "$2" --arg st "$3" --arg m "$4" '{status:$s, component:$c, state:$st, message:$m}' |
  curl -s -X POST -H 'Content-Type: application/json' --data @- http://127.0.0.1:8082/api/update; echo
