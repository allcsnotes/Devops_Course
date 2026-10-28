kubectl get pods -l app=thumbnailer
kubectl describe pod -l app=thumbnailer | sed -n '/^    State:/,/^    Ready:/p;/Limits:/,/memory:/p'
kubectl get pod -l app=thumbnailer -o jsonpath='{.items[0].status.containerStatuses[0].lastState.terminated}' | jq '{reason, exitCode}'
kubectl logs deploy/thumbnailer
cd ~/allcsvideos
sed -i 's/limits: {memory: 32Mi}/limits: {memory: 128Mi}/; s/requests: {memory: 16Mi}/requests: {memory: 96Mi}/' thumbnailer.yaml
grep -A2 'resources:' thumbnailer.yaml
kubectl apply -f thumbnailer.yaml
kubectl rollout status deployment thumbnailer
kubectl get pods -l app=thumbnailer
sleep 3; kubectl logs deploy/thumbnailer
