#!/bin/bash
# reset.sh: puts the lab back to the "before" state, so you can rehearse again:
# no app in the cluster, an empty deploy repo in Gitea, the VMs serving again, 0 % to Kubernetes, no progress rows.
# It does NOT undo your file edits in ~/migration-lab (db_pool, values-prod.yaml): change those back by hand if you
# want to replay the connection-budget problem.
set -euo pipefail
docker exec -i mig-ops bash -lc '
  export PATH=$HOME/.venvs/ansible/bin:$HOME/migration/bin:$PATH
  kubectl -n argocd delete application allcs-api --ignore-not-found; kubectl -n argocd delete appproject allcsvideos --ignore-not-found
  kubectl delete namespace allcs --ignore-not-found --wait=true
  T=$(sed -E "s|http://asha:([^@]+)@.*|\1|" ~/.git-credentials)
  curl -s -X DELETE -H "Authorization: token $T" http://10.0.201.40:3000/api/v1/repos/allcsvideos/allcsvideos-deploy
  curl -s -X POST -H "Content-Type: application/json" -H "Authorization: token $T" http://10.0.201.40:3000/api/v1/orgs/allcsvideos/repos -d "{\"name\":\"allcsvideos-deploy\",\"private\":false,\"default_branch\":\"main\"}" >/dev/null
  rm -rf /home/asha/migration/deploy/.git
  cd /home/asha/migration/ansible && ansible-playbook site.yml >/dev/null && echo "VMs reset"
  shift.sh 0 >/dev/null; : > /home/asha/migration/k6/out/events.log
  PGPASSWORD=demo-password-123 psql -h 10.0.201.20 -U postgres catalog -qc "TRUNCATE progress"
'
