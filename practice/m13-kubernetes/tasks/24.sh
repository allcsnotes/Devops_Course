kubectl get deployment storefront -o jsonpath='{.spec.strategy.rollingUpdate}{"\n"}{.spec.template.spec.containers[0].readinessProbe.httpGet}{"\n"}'
traffic(){ end=$(( $(date +%s) + $1 )); while [ $(date +%s) -lt $end ]; do curl -s --max-time 2 http://127.0.0.1:30080/ | grep -o 'version [0-9.]*' || echo FAILED; sleep 0.05; done > /tmp/traffic.txt; }
traffic 25 & sleep 3; kubectl rollout restart deployment storefront; kubectl rollout status deployment storefront; wait
sort /tmp/traffic.txt | uniq -c
cd ~/allcsvideos
sed -i 's|^        readinessProbe:|        lifecycle:\n          preStop:\n            exec: {command: ["sleep", "5"]}\n        readinessProbe:|; s/change-cause: ".*"/change-cause: "1.0.2: wait 5 s before nginx stops"/' storefront.yaml
sed -n '/- name: web/,/readinessProbe:/p' storefront.yaml
kubectl apply -f storefront.yaml
kubectl rollout status deployment storefront
kubectl apply -f storefront-html-v2.yaml
sed -i 's/{name: html, configMap: {name: storefront-html}}/{name: html, configMap: {name: storefront-html-v2}}/; s/change-cause: ".*"/change-cause: "2.0: new home page"/' storefront.yaml
kubectl diff -f storefront.yaml | grep '^[-+] '
traffic 25 & sleep 3; kubectl apply -f storefront.yaml; kubectl rollout status deployment storefront; wait
sort /tmp/traffic.txt | uniq -c
curl -s http://127.0.0.1:30080/
kubectl rollout history deployment storefront
traffic 25 & sleep 3; kubectl rollout undo deployment storefront; kubectl rollout status deployment storefront; wait
sort /tmp/traffic.txt | uniq -c
curl -s http://127.0.0.1:30080/
kubectl rollout history deployment storefront
sed -i 's/{name: html, configMap: {name: storefront-html-v2}}/{name: html, configMap: {name: storefront-html}}/; s/change-cause: ".*"/change-cause: "1.0.2: wait 5 s before nginx stops"/' storefront.yaml
kubectl apply -f storefront.yaml
kubectl diff -f storefront.yaml; echo "exit code: $?"
