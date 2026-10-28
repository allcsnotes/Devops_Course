kubectl get all
kubectl get pods --field-selector=status.phase!=Running
kubectl get pods -l tier=backend -L app,tier
kubectl get pods -l 'tier in (frontend),app!=blog' --show-labels
kubectl get configmaps,secrets
