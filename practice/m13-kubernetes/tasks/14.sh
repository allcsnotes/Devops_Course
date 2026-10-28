P=$(kubectl get pods -l app=catalog -o jsonpath='{.items[0].metadata.name}'); echo $P
kubectl get pod $P -o jsonpath='{.metadata.ownerReferences[0]}' | jq '{kind, name, controller}'
RS=$(kubectl get pod $P -o jsonpath='{.metadata.ownerReferences[0].name}'); echo $RS
kubectl get rs $RS -o jsonpath='{.metadata.ownerReferences[0]}' | jq '{kind, name, controller}'
kubectl delete pod $P
kubectl get pods -l app=catalog
kubectl scale rs $RS --replicas=4
sleep 2; kubectl get rs $RS
kubectl get pods -l app=catalog
