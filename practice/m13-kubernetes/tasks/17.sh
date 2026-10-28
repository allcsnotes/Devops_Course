kubectl exec deploy/copilot -- wget -qO- -T 3 http://catalog:8080/courses.json
kubectl get endpointslices -l kubernetes.io/service-name=catalog
kubectl describe service catalog | grep -E 'Selector|Endpoints'
kubectl get pods -l app=catalog --show-labels
kubectl get pods -l app=catalog,tier=api
cd ~/allcsvideos
sed -i 's/selector: {app: catalog, tier: api}/selector: {app: catalog}/' catalog.yaml
kubectl apply -f catalog.yaml
kubectl get endpointslices -l kubernetes.io/service-name=catalog
kubectl exec deploy/copilot -- wget -qO- -T 3 http://catalog:8080/courses.json
