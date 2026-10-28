#!/bin/bash
# Runs as root in a laptop container: one normal user, no sshd running (it is only the ssh client side).
# Usage: setup-laptop.sh <user>     up.sh calls it for asha and for priya.
set -e
u=$1
useradd -m -s /bin/bash "$u"
