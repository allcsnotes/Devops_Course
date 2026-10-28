#!/bin/sh
# Adds encryption at rest to a kubeadm kube-apiserver static pod manifest (the three edits from the Kubernetes docs task
# "Encrypting Confidential Data at Rest"): the flag, a read-only volumeMount, and a hostPath volume.
f=${1:-kube-apiserver.yaml}
sed -i \
 -e '/^    - kube-apiserver$/a\    - --encryption-provider-config=/etc/kubernetes/enc/enc.yaml' \
 -e '/^    volumeMounts:$/a\    - mountPath: /etc/kubernetes/enc\n      name: enc\n      readOnly: true' \
 -e '/^  volumes:$/a\  - hostPath:\n      path: /etc/kubernetes/enc\n      type: DirectoryOrCreate\n    name: enc' "$f"
