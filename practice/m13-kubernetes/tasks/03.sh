ls -l ~/.kube/config
kubectl config view --minify
kubectl auth whoami
kubectl auth can-i delete nodes
kubectl auth can-i '*' '*' --all-namespaces
