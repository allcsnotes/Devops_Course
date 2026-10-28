cd ~/allcsvideos
sed -i 's/CATALOG_REGION: ap-south-1/CATALOG_REGION: ap-south-2/' catalog.yaml
sed -i 's|      {"id": "devops", "title": "DevOps: From Linux to Kubernetes in Production"}|      {"id": "devops", "title": "DevOps: From Linux to Kubernetes in Production"},\n      {"id": "genai", "title": "Generative AI with Python"}|' catalog.yaml
kubectl diff -f catalog.yaml | grep '^[-+] '
kubectl apply -f catalog.yaml; date +%T
kubectl exec deploy/copilot -- wget -qO- http://catalog:8080/courses.json | grep -c '"id"'
start=$(date +%s); until [ "$(for p in $(kubectl get pods -l app=catalog -o name); do kubectl exec $p -- grep -c '"id"' /www/courses.json; done | sort -u)" = 3 ]; do sleep 2; done; echo "all catalog pods updated after $(( $(date +%s) - start )) s"; date +%T
for p in $(kubectl get pods -l app=catalog -o name); do echo "$p: $(kubectl exec $p -- grep -c '"id"' /www/courses.json) courses, $(kubectl exec $p -- printenv CATALOG_REGION)"; done
OLD=$(kubectl get rs -l app=catalog --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.labels.pod-template-hash}'); echo $OLD
kubectl rollout restart deployment catalog
kubectl rollout status deployment catalog
kubectl wait --for=delete pod -l pod-template-hash=$OLD --timeout=60s
for p in $(kubectl get pods -l app=catalog -o name); do echo "$p: $(kubectl exec $p -- printenv CATALOG_REGION)"; done
