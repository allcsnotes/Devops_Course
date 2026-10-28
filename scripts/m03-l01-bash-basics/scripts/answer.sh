#!/usr/bin/env bash
# answer.sh: read an answer, then pick a branch with case
read -p "Clear the old upload cache? [y/n] " answer

case $answer in
  y|Y|yes) echo "Clearing the cache" ;;
  n|N|no)  echo "Leaving it alone" ;;
  *)       echo "Please answer y or n" ;;
esac
