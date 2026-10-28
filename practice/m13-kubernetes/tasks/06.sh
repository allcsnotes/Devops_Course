cd ~/allcsvideos
ls
kubectl get deployment storefront
kubectl diff -f storefront.yaml; echo "exit code: $?"
kubectl apply -f storefront.yaml
kubectl rollout status deployment storefront
kubectl diff -f storefront.yaml; echo "exit code: $?"
