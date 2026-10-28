kubectl rollout status deployment blog --timeout=10s
kubectl get rs,pods -l app=blog
kubectl get deployment blog -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
NEW=$(kubectl get pods -l app=blog -o jsonpath='{range .items[?(@.status.containerStatuses[0].ready==false)]}{.metadata.name}{end}'); echo $NEW
kubectl describe pod $NEW | grep -E 'Image:|Port:|Readiness:|Warning'
kubectl exec $NEW -- grep -m1 listen /etc/nginx/conf.d/default.conf
kubectl rollout history deployment blog
kubectl rollout undo deployment blog
kubectl rollout status deployment blog
kubectl get rs -l app=blog
kubectl rollout history deployment blog
cd ~/allcsvideos
sed -i 's/containerPort: 80}/containerPort: 8080}/; s/"1.1: run as non-root (nginx-unprivileged image)"/"1.1.1: non-root image, listens on 8080"/' blog.yaml
kubectl diff -f blog.yaml | grep '^[-+] '
kubectl apply -f blog.yaml
kubectl rollout status deployment blog
kubectl rollout history deployment blog
