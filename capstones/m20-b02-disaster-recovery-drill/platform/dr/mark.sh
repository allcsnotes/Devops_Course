#!/usr/bin/env bash
# dr/mark.sh "<event>": add a line to the shared drill log (the scribe's timeline; restore.sh uses the same format)
echo "$(date '+%F %T.%3N') $*" >> /srv/drill/events.log; echo "$(date +%T) == $*"
