# OpenShift Virtualization (CNV) — dev only, tanpa ACM

```sh
kubectl --kubeconfig=dev/dev.kubeconfig apply -f 00-namespace.yaml -f 01-subscription.yaml
# tunggu CSV Succeeded, lalu:
kubectl --kubeconfig=dev/dev.kubeconfig apply -f 02-hyperconverged.yaml
```

| File | Isi |
| --- | --- |
| `00-namespace.yaml` | ns `openshift-cnv` |
| `01-subscription.yaml` | OperatorGroup (targetNamespaces, karena CNV tidak support AllNamespaces) + Subscription `kubevirt-hyperconverged` channel `stable` (v4.22.12) |
| `02-hyperconverged.yaml` | CR singleton: eviction LiveMigrate, workloadUpdate LiveMigrate, liveMigration (5/2/150/150, no auto-converge/post-copy/bandwidth-cap), vmiCPUAllocationRatio 10 |

Yang default (sengaja unset): TLS Intermediate, cert rotation, CPU host-model,
feature gates GA (CPUManager/Snapshot/ExpandDisks), bridge-on-Multus untuk VM
(`permitBridgeInterfaceOnPodNetwork` default false).

## Catatan

- **API v1 nested**, bukan v1beta1 flat: `spec.virtualization.*`. Server
  meng-convert v1beta1 otomatis, tapi tulis langsung v1 agar drift-bersih.
- **Jangan buat CR KubeVirt manual** — HCO own dan overwrite CR
  `kubevirt-kubevirt-hyperconverged`. Semua tuning lewat HyperConverged.
- **KVM**: worker m6a.4xlarge expose `/dev/kvm` (`devices.kubevirt.io/kvm=1k`,
  nested virt OK). Master bertaint, virt-handler hanya di worker (desired 1,
  benar).
- **NMState CR skip** (keputusan user): handler belum jalan. Kalau butuh
  NodeNetworkConfigPolicy untuk bridge VLAN, buat CR `NMState/nmstate` dulu.
- **NAD skip**: bridge Multus VLAN + IPAM nyusul saat ada detail VLAN ID/subnet.

## Verifikasi

```sh
K=dev/dev.kubeconfig
kubectl --kubeconfig=$K get hyperconverged -n openshift-cnv   # Available=True
kubectl --kubeconfig=$K get kubevirt -n openshift-cnv         # PHASE Deployed
kubectl --kubeconfig=$K get ds virt-handler -n openshift-cnv  # 1/1 di worker
kubectl --kubeconfig=$K get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" kvm="}{.status.capacity.devices\.kubevirt\.io\/kvm}{"\n"}{end}'
```
