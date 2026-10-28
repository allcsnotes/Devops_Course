#!/bin/bash
# count-errors.sh: how many storefront-bff traces with an error status did Tempo store since the last load run started?
curl -s -G localhost:3200/api/search \
  --data-urlencode 'q={ resource.service.name = "storefront-bff" && status = error }' \
  --data-urlencode "start=$(cat /tmp/load-start)" --data-urlencode "end=$(date +%s)" \
  --data-urlencode limit=1000 | jq '.traces | length'
