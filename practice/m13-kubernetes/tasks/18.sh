kubectl exec deploy/copilot -- cat /etc/resolv.conf
kubectl get service kube-dns -n kube-system
kubectl exec deploy/copilot -- nslookup catalog.allcsvideos.svc.cluster.local
kubectl get service catalog
kubectl -n allcsvideos-staging exec deploy/storefront -- cat /etc/resolv.conf
kubectl -n allcsvideos-staging exec deploy/storefront -- wget -qO- -T 3 http://catalog:8080/courses.json
kubectl -n allcsvideos-staging exec deploy/storefront -- wget -qO- -T 3 http://catalog.allcsvideos:8080/courses.json
