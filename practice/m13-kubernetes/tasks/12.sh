P=$(kubectl get pods -l app=copilot -o name); echo $P
time kubectl delete $P
kubectl get pods -l app=copilot
kubectl exec deploy/copilot -- ps -o pid,args
kubectl get deploy copilot -o jsonpath='{.spec.template.spec.terminationGracePeriodSeconds}{"\n"}'
kubectl get events --field-selector involvedObject.name=${P#pod/}
kubectl run trap-test --image=busybox:1.37.0 --restart=Never -- sh -c "trap 'echo got SIGTERM, bye; exit 0' TERM; while true; do sleep 1; done"
kubectl wait --for=condition=Ready pod/trap-test --timeout=60s
time kubectl delete pod trap-test
