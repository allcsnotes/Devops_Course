# ${{ values.name }}

${{ values.description }}

Made from the platform team's `python-service` golden path. Owner: `${{ values.owner }}`.

- Run the tests: `python3 -m unittest -v`
- CI: `.gitea/workflows/ci.yaml` (tests, Dockerfile lint, Helm lint)
- Deploy: `deploy/chart` (Helm), synced by Argo CD from `deploy/argocd-app.yaml`
