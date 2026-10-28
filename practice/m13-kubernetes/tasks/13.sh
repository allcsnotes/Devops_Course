cd ~/allcsvideos
kubectl get deployment catalog
kubectl apply -f catalog.yaml
grep -n -A1 -E 'matchLabels|^    metadata' catalog.yaml
sed -i 's/labels: {app: catalog-api, tier: backend}/labels: {app: catalog, tier: backend}/' catalog.yaml
kubectl apply -f catalog.yaml
kubectl rollout status deployment catalog
kubectl get deploy,rs,pods -l app=catalog
kubectl logs deploy/catalog
