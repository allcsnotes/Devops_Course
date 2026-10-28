#!/usr/bin/env bash
# archive-logs.sh: copy the nginx logs into today's archive folder
dest=$HOME/archive/$(date +%F)
mkdir -p $dest
cd $dest
for f in $(ls /var/log/nginx/*.log); do
  cp $f .
done

count() {
  local n=$(ls | wc -l)
  echo "$n files archived"
}
count
