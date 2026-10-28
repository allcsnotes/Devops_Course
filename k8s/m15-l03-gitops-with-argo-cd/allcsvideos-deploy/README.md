# allcsvideos-deploy

The desired state of allcsvideos.com on Kubernetes. Argo CD watches this repository and makes the cluster match it.
Change the cluster by changing this repository (a commit or a pull request), never with kubectl.

- storefront/  the web storefront (Kustomize base + dev, staging, prod overlays)
- api/         the API (base + prod overlay; a database migration runs before every sync)
- monitoring/  placeholder for Module 16
