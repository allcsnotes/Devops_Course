#!/usr/bin/env bash
# Installs the CLI tools this build used into ~/bin (Linux x86_64, e.g. AWS CloudShell):
#   helm v4.3.1 (sha256-verified), argocd v3.5.5, kubectl-argo-rollouts v1.10.1.
# CloudShell keeps $HOME between sessions, so this runs once. kubectl and the AWS CLI are already there.
set -euo pipefail
mkdir -p ~/bin && cd "$(mktemp -d)"

curl -fsSLo helm.tgz https://get.helm.sh/helm-v4.3.1-linux-amd64.tar.gz
echo "0403a88ae20913d11b10a2467b50087721fea7581736da6b9d3992f5357fe54b  helm.tgz" | sha256sum -c -
tar -xzf helm.tgz && mv linux-amd64/helm ~/bin/helm

# compare these two with the checksums published on their GitHub release pages
curl -fsSLo ~/bin/argocd https://github.com/argoproj/argo-cd/releases/download/v3.5.5/argocd-linux-amd64
curl -fsSLo ~/bin/kubectl-argo-rollouts https://github.com/argoproj/argo-rollouts/releases/download/v1.10.1/kubectl-argo-rollouts-linux-amd64
chmod +x ~/bin/helm ~/bin/argocd ~/bin/kubectl-argo-rollouts
sha256sum ~/bin/argocd ~/bin/kubectl-argo-rollouts

case ":$PATH:" in *":$HOME/bin:"*) ;; *) echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc; echo "run: source ~/.bashrc";; esac
helm version --short
