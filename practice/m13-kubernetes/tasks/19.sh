cd ~/allcsvideos
kubectl expose deployment catalog --name=catalog-headless --cluster-ip=None --port=8080 --dry-run=client -o yaml > catalog-headless.yaml
grep -A8 '^spec:' catalog-headless.yaml
kubectl apply -f catalog-headless.yaml
kubectl get services catalog catalog-headless
kubectl exec deploy/copilot -- nslookup catalog-headless.allcsvideos.svc.cluster.local
kubectl get pods -l app=catalog -o wide
