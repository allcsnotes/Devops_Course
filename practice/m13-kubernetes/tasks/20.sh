kubectl get pods -l app=worker
kubectl logs deploy/worker
kubectl get configmap worker-config -o jsonpath='{.data}{"\n"}'
cd ~/allcsvideos
sed -i 's/QUEUE_ULR:/QUEUE_URL:/' worker.yaml
kubectl apply -f worker.yaml
kubectl rollout restart deployment worker
kubectl rollout status deployment worker
kubectl get pods -l app=worker
kubectl logs deploy/worker
