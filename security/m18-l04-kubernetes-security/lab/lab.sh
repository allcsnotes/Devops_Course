#!/usr/bin/env bash
# lab.sh: the M18-L04 kind lab (from the Module 13 lab).
#   ./lab.sh up      build + start the tool box (docker CLI, kind, kubectl, helm, cosign), the lab registry
#                    (registry.lab:5000 inside the cluster, localhost:5001 on your laptop), the cluster "k8s-sec",
#                    copy manifests/ and app/ into the tool box, and push the 1.0 images of catalog and api
#   ./lab.sh sh      a shell (asha@lab) in the tool box, in ~/allcsvideos: every kubectl command of the lesson runs here
#   ./lab.sh sync    copy manifests/ and app/ into the tool box again (after you edit them)
#   ./lab.sh down    delete the cluster, the tool box, the registry and the lab images (the shared "kind" network stays)
set -euo pipefail
P=k8s-sec; TOOLS=$P-tools; IMG=$P-tools:1.0; REG=$P-registry
NODE_IMAGE=kindest/node:v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(dirname "$HERE")
ex(){ docker exec -i $TOOLS "$@"; }
sync(){ ex mkdir -p /home/asha/allcsvideos
        docker cp "$ROOT/manifests/." $TOOLS:/home/asha/allcsvideos/ >/dev/null
        docker cp "$ROOT/app" $TOOLS:/home/asha/allcsvideos/ >/dev/null
        docker exec -u 0 $TOOLS chown -R asha:asha /home/asha/allcsvideos; }
case ${1:-} in
  up)
    docker build -q -t $IMG "$HERE" >/dev/null
    docker ps -a --format '{{.Names}}' | grep -qx $TOOLS || \
      docker run -d --name $TOOLS --hostname lab --label course=devops --network host \
        -v /var/run/docker.sock:/var/run/docker.sock $IMG >/dev/null
    docker cp "$HERE/kind-cluster.yaml" $TOOLS:/home/asha/kind-cluster.yaml
    ex kind get clusters 2>/dev/null | grep -qx $P || ex kind create cluster --name $P --image $NODE_IMAGE --config /home/asha/kind-cluster.yaml --wait 300s
    # the lab registry, registry:3.1.2, on the kind network as registry.lab (the kind docs' local-registry pattern)
    docker ps -a --format '{{.Names}}' | grep -qx $REG || \
      docker run -d --name $REG --label course=devops --restart no -p 127.0.0.1:5001:5000 registry:3.1.2 >/dev/null
    docker network inspect kind -f '{{range .Containers}}{{.Name}} {{end}}' | tr ' ' '\n' | grep -qx $REG || \
      docker network connect --alias registry.lab kind $REG
    docker exec $P-control-plane mkdir -p /etc/containerd/certs.d/registry.lab:5000
    printf '[host."http://registry.lab:5000"]\n  capabilities = ["pull", "resolve"]\n' | docker exec -i $P-control-plane cp /dev/stdin /etc/containerd/certs.d/registry.lab:5000/hosts.toml
    sync
    # the lab services' images: the same tiny image for catalog and api
    ex sh -c 'cd /home/asha/allcsvideos && for s in catalog api; do docker build -q --label course=devops -t localhost:5001/allcs/$s:1.0 --build-arg SVC=$s --build-arg VERSION=1.0 app >/dev/null && docker push -q localhost:5001/allcs/$s:1.0; done'
    ex kubectl get nodes ;;
  sh) docker exec -it -w /home/asha/allcsvideos $TOOLS bash ;;
  sync) sync ;;
  down)
    if docker ps --format '{{.Names}}' | grep -qx $TOOLS; then ex kind delete cluster --name $P || true; fi
    for c in $(docker ps -a --format '{{.Names}} {{.Label "io.x-k8s.kind.cluster"}}' | awk -v p=$P '$2==p {print $1}'); do docker rm -f "$c" >/dev/null; done
    docker rm -f -v $REG >/dev/null 2>&1 || true
    docker rm -f $TOOLS >/dev/null 2>&1 || true
    for i in $(docker images --format '{{.Repository}}:{{.Tag}}' | grep -E "^(localhost:5001/allcs/|$P)"); do docker rmi "$i" >/dev/null || true; done
    echo "removed cluster $P, $TOOLS, $REG and the lab images (the shared 'kind' network is left alone)" ;;
  *) sed -n '2,9p' "$0"; exit 1 ;;
esac
