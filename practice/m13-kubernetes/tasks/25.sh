kubectl describe secret mail-creds | sed -n '/^Data/,$p'
kubectl get secret mail-creds -o jsonpath='{.data.password}'; echo
kubectl get secret mail-creds -o jsonpath='{.data.password}' | base64 -d; echo
echo -n 'demo-smtp-password-123' | base64
kubectl get secret mail-creds -o jsonpath='{.metadata.annotations.kubectl\.kubernetes\.io/last-applied-configuration}' | jq .stringData
kubectl exec deploy/mailer -- cat /etc/mailer/smtp-password; echo
grep -n -A3 '^stringData' ~/allcsvideos/mailer.yaml
kubectl -n kube-system get pod kube-apiserver-m13lab-control-plane -o yaml | grep -c encryption-provider-config
E='--cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key'
kubectl -n kube-system exec etcd-m13lab-control-plane -- etcdctl $E get /registry/secrets/allcsvideos/mail-creds | hexdump -C | tail -6
kubectl -n kube-system exec etcd-m13lab-control-plane -- etcdctl $E get /registry/secrets/allcsvideos/mail-creds | strings | grep demo-smtp
