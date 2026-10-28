kubectl get pods -l app=api
kubectl logs deploy/api -c wait-for-db --tail=3
kubectl get svc
kubectl get pods -l app=db --show-labels
cd ~/allcsvideos
kubectl expose deployment db --port=5432 --target-port=postgres --dry-run=client -o yaml > db-service.yaml
cat db-service.yaml
kubectl apply -f db-service.yaml
kubectl get endpointslices -l kubernetes.io/service-name=db
kubectl wait --for=condition=Ready pod -l app=api --timeout=60s
kubectl logs deploy/api -c wait-for-db --tail=2
kubectl logs deploy/api
