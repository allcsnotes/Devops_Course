#!/usr/bin/env bash
# int.sh: a trap on INT that forgets to exit
cleanup() { echo "cleaning up"; }
trap cleanup INT

echo "step 1: waiting"
sleep 30
echo "step 2: deleting old releases"
