#!/usr/bin/env bash
# cleanup.sh: delete the files of old releases (staged demo, sandbox only)

cd "$HOME/sandbox/releases/old"
rm -f *
echo "cleanup done"
