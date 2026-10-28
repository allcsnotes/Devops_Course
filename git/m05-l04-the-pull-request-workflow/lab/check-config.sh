#!/bin/bash
# check-config FILE: loads an hc config exactly as bin/hc does (lib/checks.sh load_conf), without running any checks.
die(){ echo "hc: $1"; exit 3; }
source hc/lib/checks.sh
load_conf "$1"
echo "config ok: $1"
