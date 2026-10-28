cd ~/allcsvideos
kubectl get rs -l app=catalog
sed -i 's/replicas: 2/replicas: 3/' catalog.yaml
kubectl diff -f catalog.yaml | grep '^[-+] '
kubectl apply -f catalog.yaml
kubectl rollout status deployment catalog
kubectl get rs -l app=catalog
kubectl diff -f catalog.yaml; echo "exit code: $?"
