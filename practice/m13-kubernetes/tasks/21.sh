kubectl get pods -l app=mailer
kubectl describe pod -l app=mailer | sed -n '/^Events:/,$p' | tail -2
kubectl describe secret mail-creds | sed -n '/^Data/,$p'
cd ~/allcsvideos
grep -n -B1 -A2 'items:' mailer.yaml
sed -i 's/- {key: smtp-password, path: smtp-password}/- {key: password, path: smtp-password}/' mailer.yaml
kubectl apply -f mailer.yaml
kubectl rollout status deployment mailer
kubectl logs deploy/mailer
kubectl exec deploy/mailer -- ls -la /etc/mailer
kubectl exec deploy/mailer -- df -h /etc/mailer
