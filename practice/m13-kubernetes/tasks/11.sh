P=$(kubectl get pods -l app=storefront -o jsonpath='{.items[0].metadata.name}'); echo $P
kubectl get pod $P
kubectl get pod $P -o jsonpath='init: {.spec.initContainers[*].name} (restartPolicy {.spec.initContainers[0].restartPolicy}){"\n"}app:  {.spec.containers[*].name}{"\n"}'
kubectl get pod $P -o jsonpath='{.status.podIP}{"\n"}'
kubectl exec $P -c web -- wget -qO /dev/null 127.0.0.1/
kubectl exec $P -c web -- wget -qO /dev/null 127.0.0.1/courses
sleep 1; kubectl logs $P -c log-shipper --tail=2
kubectl exec $P -c log-shipper -- ls -l /var/log/nginx
kubectl exec $P -c log-shipper -- ls /usr/share/nginx
