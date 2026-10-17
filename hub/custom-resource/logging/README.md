```sh
oc apply -f rbac.yaml
```

RoleClusterBinding di atas setara dengan:

```sh
oc adm policy add-cluster-role-to-user logging-collector-logs-writer -z logging-collector -n openshift-logging
oc adm policy add-cluster-role-to-user collect-application-logs -z logging-collector -n openshift-logging
oc adm policy add-cluster-role-to-user collect-infrastructure-logs -z logging-collector -n openshift-logging
```

ClusterRole `logging-collector-logs-writer`, `collect-application-logs`, dan `collect-infrastructure-logs` dibuat oleh cluster-logging-operator — apply `rbac.yaml` setelah operator terpasang.
