#!/usr/bin/env bash
# opts.sh: parse options with getopts
verbose=0
limit=80

while getopts ':hvt:' opt; do
  case $opt in
    h)  echo "usage: opts.sh [-h] [-v] [-t PERCENT] [MOUNT...]"; exit 0 ;;
    v)  verbose=1 ;;
    t)  limit=$OPTARG ;;
    :)  echo "opts.sh: -$OPTARG needs a value" >&2; exit 2 ;;
    \?) echo "opts.sh: unknown option -$OPTARG" >&2; exit 2 ;;
  esac
done
shift $(( OPTIND - 1 ))

echo "verbose=$verbose limit=$limit"
echo "mounts: $*"
