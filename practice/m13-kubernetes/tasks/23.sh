curl -sS --max-time 5 http://127.0.0.1:30080/
kubectl get service storefront
kubectl get endpointslices -l kubernetes.io/service-name=storefront
kubectl get pods -l app=storefront -o jsonpath='{.items[0].spec.containers[0].ports}{"\n"}'
cd ~/allcsvideos
sed -i 's/    targetPort: 8080/    targetPort: http/' storefront.yaml
kubectl apply -f storefront.yaml
kubectl get endpointslices -l kubernetes.io/service-name=storefront
curl -sS --retry 5 --retry-connrefused --retry-delay 1 --max-time 5 http://127.0.0.1:30080/
curl -sS --max-time 10 -o /dev/null -w 'HTTP %{http_code} after %{time_total} s\n' http://127.0.0.1:30080/api/courses.json
for p in $(kubectl get pods -l app=storefront -o name); do kubectl exec $p -c web -- grep -h 'timed out' /var/log/nginx/error.log; done | tail -1
kubectl get configmap storefront-nginx -o jsonpath='{.data.default\.conf}' | grep proxy_pass
kubectl get service catalog
sed -i 's|proxy_pass http://catalog:80/;|proxy_pass http://catalog:8080/;|' storefront.yaml
kubectl apply -f storefront.yaml; date +%T
until [ "$(for p in $(kubectl get pods -l app=storefront -o name); do kubectl exec $p -c web -- cat /etc/nginx/conf.d/default.conf | grep -c 'catalog:8080'; done | sort -u)" = 1 ]; do sleep 2; done; date +%T
curl -sS --max-time 10 -o /dev/null -w 'HTTP %{http_code}\n' http://127.0.0.1:30080/api/courses.json
kubectl rollout restart deployment storefront
kubectl annotate deployment storefront kubernetes.io/change-cause="1.0.1: catalog API on port 8080" --overwrite
sed -i 's/change-cause: ".*"/change-cause: "1.0.1: catalog API on port 8080"/' storefront.yaml
kubectl rollout status deployment storefront
curl -sS --retry 5 --retry-connrefused --retry-delay 1 --max-time 5 -w 'HTTP %{http_code}\n' http://127.0.0.1:30080/api/courses.json
kubectl rollout history deployment storefront
kubectl diff -f storefront.yaml; echo "exit code: $?"
