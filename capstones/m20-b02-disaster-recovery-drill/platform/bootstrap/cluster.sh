#!/usr/bin/env bash
# bootstrap/cluster.sh: build the production Kubernetes cluster from this repo. After the last step, Git takes over:
# Argo CD installs External Secrets, the platform objects and the allcs app from apps/root.
set -euo pipefail
cd "$(dirname "$0")/.."
C=dr; IP=10.0.202.30
NODE=kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed
say(){ echo "$(date +%T) cluster: $*"; }
say "1/5 kind create cluster $C (kindest/node v1.36.4)"
kind create cluster --name $C --image $NODE --config bootstrap/kind-cluster.yaml --kubeconfig /tmp/kind-$C --wait 300s 2>&1 | grep -E '^ ✓|^ •' || true
say "2/5 join the node to the lab network as $IP, registry.lab:5000 for containerd"
docker network connect --ip $IP dr-net $C-control-plane
docker exec $C-control-plane sh -c 'mkdir -p /etc/containerd/certs.d/registry.lab:5000 && printf "[host.\"http://10.0.202.7:5000\"]\n  capabilities = [\"pull\", \"resolve\"]\n" > /etc/containerd/certs.d/registry.lab:5000/hosts.toml'
mkdir -p ~/.kube && sed -E "s#server: https://[^ ]+#server: https://$IP:6443#" /tmp/kind-$C > ~/.kube/config && chmod 600 ~/.kube/config && rm /tmp/kind-$C
kubectl get nodes --no-headers
say "3/5 Argo CD v3.5.6 (core) from bootstrap/argocd"
kubectl apply -k bootstrap/argocd --server-side --force-conflicts >/dev/null 2>&1 || true     # CRDs first (the project may fail once)
kubectl wait --for condition=established crd/applications.argoproj.io crd/appprojects.argoproj.io --timeout 120s >/dev/null
kubectl apply -k bootstrap/argocd --server-side --force-conflicts >/dev/null      # again: the default project needs its CRD first
say "4/5 Git read access for Argo CD (token from the break-glass folder)"
kubectl -n argocd create secret generic repo-platform --from-literal=type=git \
  --from-literal=url=http://10.0.202.5:3000/allcsvideos/platform.git --from-literal=username=argocd-bot \
  --from-file=password=$HOME/break-glass/argocd-git-token >/dev/null
kubectl -n argocd label secret repo-platform argocd.argoproj.io/secret-type=repository >/dev/null
say "5/5 the root app: from here on, Git is the source of truth"
kubectl apply -f bootstrap/root-app.yaml
