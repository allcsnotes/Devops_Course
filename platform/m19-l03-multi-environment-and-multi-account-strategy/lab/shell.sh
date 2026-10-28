#!/usr/bin/env bash
# shell.sh asha|priya|rahul|ci : open a terminal as one person on the lab laptop, or as CI on build-01.
case ${1:-} in
  asha|priya|rahul) exec docker exec -it -u "$1" -e HOME="/home/$1" -w "/home/$1" lab-laptop bash ;;
  ci) exec docker exec -it -w /work/allcsvideos-api lab-build bash ;;
  *) echo "usage: $0 asha|priya|rahul|ci"; exit 1 ;;
esac
