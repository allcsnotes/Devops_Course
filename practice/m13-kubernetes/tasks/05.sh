kubectl api-resources | grep -E '^NAME|^(configmaps|endpointslices|namespaces|nodes|pods|replicasets|secrets|services) '
kubectl explain deployment.spec.progressDeadlineSeconds
kubectl explain pod.spec.terminationGracePeriodSeconds | grep -E 'FIELD|Defaults'
kubectl explain service.spec.ports.targetPort
