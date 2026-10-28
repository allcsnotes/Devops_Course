kubectl get pods
kubectl config current-context
kubectl config get-contexts
kubectl config use-context kind-m13lab
kubectl config set-context --current --namespace=allcsvideos
kubectl config get-contexts
kubectl get deployments
echo 'kctx(){ kubectl config current-context; }' >> ~/.bashrc
echo 'PS1="[\$(kctx)] \u@\h:\w\$ "' >> ~/.bashrc
tail -2 ~/.bashrc
