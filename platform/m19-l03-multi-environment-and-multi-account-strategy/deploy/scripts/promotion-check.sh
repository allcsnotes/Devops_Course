#!/bin/bash
# promotion-check: an environment may only receive the image digest that the environment before it
# runs on main today. dev <- CI builds, staging <- dev, prod <- staging. Nothing is ever rebuilt.
set -u
base=${1:-origin/main}
digest(){ git show "$1:envs/$2/kustomization.yaml" 2>/dev/null | sed -n 's/.*digest: //p'; }
fail=0
for pair in staging:dev prod:staging; do
  env=${pair%%:*}; from=${pair##*:}
  new=$(digest HEAD "$env"); old=$(digest "$base" "$env"); src=$(digest "$base" "$from")
  if [[ $new == "$old" ]]; then echo "$env: unchanged (${new:0:19})"; continue; fi
  if [[ $new == "$src" ]]; then echo "$env: ${new:0:19} OK, it is what $from runs on main"
  else echo "$env: ${new:0:19} REFUSED, $from runs ${src:0:19} on main"; fail=1; fi
done
exit $fail
