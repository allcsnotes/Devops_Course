apiVersion: policies.kyverno.io/v1
kind: ImageValidatingPolicy
metadata:
  name: verify-allcs-images
spec:
  validationActions: [Deny]
  matchConstraints:
    resourceRules:
    - apiGroups: [""]
      apiVersions: [v1]
      operations: [CREATE, UPDATE]
      resources: [pods]
  matchImageReferences:
  - glob: "registry.lab:5000/allcs/*"
  credentials:
    allowInsecureRegistry: true     # lab registry speaks plain HTTP
  attestors:
  - name: ci-key
    cosign:
      key:
        data: |
PUBKEY
      ctlog:
        insecureIgnoreTlog: true    # lab: no transparency log
  validations:
  - expression: >-
      images.containers.map(image, verifyImageSignatures(image, [attestors["ci-key"]])).all(e, e > 0)
    message: "allcs images must be signed by the CI key"
