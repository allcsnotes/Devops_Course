kubectl get pods -l app=copilot
kubectl describe pod -l app=copilot | sed -n '/^Events:/,$p'
cd ~/allcsvideos
grep -n 'image:' copilot.yaml
sed -i 's/busybox:1.37.0-muscl/busybox:1.37.0/' copilot.yaml
kubectl diff -f copilot.yaml | grep '^[-+] '
kubectl apply -f copilot.yaml
kubectl rollout status deployment copilot
kubectl get pods -l app=copilot
kubectl exec deploy/copilot -- wget -qO- 127.0.0.1:8080/index.json
