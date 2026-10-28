#!/usr/bin/env bash
# dr/vault-k8s-auth.sh: tell Vault how to check service account tokens from THIS cluster: its API address, its CA
# certificate, and the vault-reviewer token. Every new cluster has a new CA and new tokens.
set -euo pipefail
export VAULT_TOKEN=${VAULT_TOKEN:-$(jq -r .root_token ~/break-glass/vault-init.json)}
until kubectl get secret vault-reviewer-token -n kube-system -o jsonpath='{.data.token}' 2>/dev/null | grep -q .; do sleep 2; done
kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > /tmp/k8s-ca.crt
vault write auth/kubernetes/config kubernetes_host=https://10.0.202.30:6443 kubernetes_ca_cert=@/tmp/k8s-ca.crt \
  token_reviewer_jwt="$(kubectl get secret vault-reviewer-token -n kube-system -o jsonpath='{.data.token}' | base64 -d)"
rm -f /tmp/k8s-ca.crt
