# Shell helpers used in the build. Load them with:  source helpers.sh
# (run from the folder that holds this file; needs kubectl, jq and git)

# hit N: send N requests to the storefront Service from inside the cluster (from the Gitea pod, because the
# Service is a ClusterIP) and count the answers by version and pod.
hit() {
  kubectl exec -n git deploy/gitea -- sh -c "for i in \$(seq 1 $1); do wget -qO- http://storefront.allcsvideos.svc/; done" \
    | jq -r '"\(.version) \(.hostname)"' | sort | uniq -c
}

# waitphase PHASE: poll the Rollout every 6 s until .status.phase is PHASE (Paused, Healthy, ...)
waitphase() {
  local i P
  for i in $(seq 1 50); do
    P=$(kubectl get rollout storefront -n allcsvideos -o jsonpath='{.status.phase}')
    [ "$P" = "$1" ] && break
    sleep 6
  done
  echo "phase $P after $((i*6))s"
}

# push: git push to the in-cluster Gitea through the port-forward on localhost:3000.
# The token stays in $TOKEN and is sent as an HTTP header, so it is never written to .git/config.
push() {
  git -c http.extraHeader="Authorization: Basic $(printf 'asha:%s' "$TOKEN" | base64 -w0)" push -q origin main
}
