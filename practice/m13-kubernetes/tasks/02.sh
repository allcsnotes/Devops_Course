kubectl get nodes -o wide
kubectl get pods -n kube-system -o wide
docker ps --filter label=io.x-k8s.kind.cluster=m13lab --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'
docker exec m13lab-control-plane systemctl is-active kubelet containerd
docker exec m13lab-control-plane ls /etc/kubernetes/manifests
kubectl get --raw /readyz; echo
