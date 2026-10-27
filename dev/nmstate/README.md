# NMState — dev

## Yang applied di dev

`00-nmstate.yaml` — CR singleton `NMState/nmstate` (sudah applied).
Mengaktifkan handler DaemonSet (2/2) + CRD NNCP/NNCE/NNS. Tanpa CR ini
operator NMState idle.

NNS dev confirm: tiap node cuma 1 ethernet (`ens5`), IP cluster di `br-ex`
(OVS). Tidak ada NIC kedua untuk bond.

```sh
kubectl --kubeconfig=dev/dev.kubeconfig apply -f 00-nmstate.yaml
```

## Yang JANGAN di-apply di dev (on-prem only)

`01-nncp-vm-network-bond.yaml` — NNCP `vm-network-bond`: bond1 802.3ad LACP
(enp2s0f0+enp2s0f1, cross-bonding NIC kedua) + VLAN 100/200 + Linux bridge
br-vm100/br-vm200. bond0 = primary OVN-K, jangan sentuh. Server dry-run
lolos. Sesuaikan nama NIC, VLAN ID, nodeSelector sebelum apply di bare metal.

`02-nad-vm-network.yaml` — NAD bridge `vm-net-100`/`vm-net-200` (Whereabouts)
untuk interface VM. Sesuaikan subnet + range.

Kenapa tidak bisa di dev/AWS:

- LACP butuh switch yang ngomong 802.3ad; VPC tidak support.
- 1 ENI = 1 port virtual; bond butuh ≥2 interface.
- Trunk ENI AWS hanya untuk traffic lokal satu host (VPC tidak forward
  802.1Q antar host) — tidak bisa untuk segmentasi VM cluster-wide.
- Untuk VM network antar-node di AWS pakai Multus + OVN-K secondary
  (Geneve overlay), bukan Linux bridge + VLAN.

## Verifikasi

```sh
K=dev/dev.kubeconfig
kubectl --kubeconfig=$K get ds nmstate-handler -n openshift-nmstate  # 2/2
kubectl --kubeconfig=$K get nns -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
# di on-prem setelah NNCP: kubectl get nncp vm-network-bond -o jsonpath='{.status.conditions}'
```
