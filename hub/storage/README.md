<https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/4.22>
<https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/4.22/html/deploying_openshift_data_foundation_on_any_platform/index>
<https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/storage/persistent-storage-using-local-storage>

# Storage

Dua jalur, **pilih satu** — jangan jalankan bersamaan di device yang sama:

| Jalur | Manifest | Keterangan |
| --- | --- | --- |
| LSO polos | `local-volume/` | PV statis dari disk mentah, StorageClass `lvs-sc` |
| ODF internal | `odf/` | Ceph di atas PV dari `lvs-sc` (butuh `local-volume/` lebih dulu) |

ODF internal mode memakai LSO sebagai backing storage, jadi `local-volume/`
harus ada. Yang dilarang adalah mengelola device yang sama dari dua
`LocalVolumeSet`/`LocalVolume` berbeda.

## Memakai storage ODF dari node infra

Pod yang di-pin ke node infra (mis. monitoring) tidak bisa memakai PVC ODF
sebelum CSI nodeplugin ODF juga jalan di sana. Node infra bertaint `infra=node`
(`compute/machineSets/infra.yaml`), yang **tidak** ada di toleration nodeplugin:

```text
node infra   ebs.csi.aws.com=True   rbd=False   cephfs=False
nodeplugin   tolerations=[node.ocs.openshift.io/storage=true:NoSchedule]
```

Gejalanya:

```text
AttachVolume.Attach failed for volume "pvc-..." :
CSINode ip-... does not contain driver openshift-storage.rbd.csi.ceph.com
```

Perbaikannya `odf/csiNodePluginTolerations.yaml`:

```sh
oc apply -f storage/odf/csiNodePluginTolerations.yaml
oc get ds -n openshift-storage     # desired harus == jumlah node infra + odf + worker
```

**Kenapa lewat `Driver`, bukan `OperatorConfig`.** `ocs-client-operator` menimpa
`OperatorConfig ceph-csi-operator-config` dari template hardcoded setiap
reconcile (`pkg/templates/csi.go` → `templates.CSIOperatorConfigSpec.DeepCopyInto`),
jadi patch ke sana selalu di-revert — sudah diuji. `Driver.spec.nodePlugin.tolerations`
tidak ditimpa: bertahan >45 detik dan `desired` nodeplugin naik 5 → 8.

**Apply ulang setelah upgrade ODF** — CSV baru bisa me-reset `Driver`.

### StorageClass untuk monitoring

Pakai `ocs-storagecluster-ceph-rbd`, **jangan** `ocs-storagecluster-cephfs`.
CephFS adalah RWX network filesystem, sedangkan Prometheus TSDB dan Alertmanager
butuh RWO block device.


## Taint dan label node

Node odf dibuat `compute/machineSets/odf.yaml`:

```yaml
taints:
  - key: node.ocs.openshift.io/storage
    value: 'true'
    effect: NoSchedule
metadata:
  labels:
    node-role.kubernetes.io/odf: ''                   # pinning
    cluster.ocs.openshift.io/openshift-storage: ''     # nodeAffinity bawaan ODF
```

**Key taint bukan pilihan bebas.** Pakai `node.ocs.openshift.io/storage`, jangan
key kustom seperti `odf=node`, karena:

- `ocs-client-operator` menulis toleration CSI nodeplugin dari template
  hardcoded (`pkg/templates/csi.go`), selalu:

  ```go
  Tolerations: []corev1.Toleration{{
      Effect:   corev1.TaintEffectNoSchedule,
      Key:      "node.ocs.openshift.io/storage",
      Operator: corev1.TolerationOpEqual,
      Value:    "true",
  }}
  ```

  Toleration ini tidak bisa diubah: operator menimpa `OperatorConfig
  ceph-csi-operator-config` setiap reconcile
  (`templates.CSIOperatorConfigSpec.DeepCopyInto`). Patch manual akan di-revert.

- NodeAffinity bawaan ODF memakai label
  `cluster.ocs.openshift.io/openshift-storage` (`pkg/defaults/placements.go`,
  `DefaultNodeAffinity`). Tanpa label itu, daemon Ceph tidak menemukan node.

Akibat kalau memakai key kustom: CSI nodeplugin tidak bisa masuk node odf →
driver `openshift-storage.rbd.csi.ceph.com` tidak terdaftar di CSINode node itu
→ semua PVC RBD gagal attach:

```text
AttachVolume.Attach failed for volume "pvc-..." :
CSINode ip-...-78... does not contain driver openshift-storage.rbd.csi.ceph.com
```

Label bernilai kosong itu normal. `-l node-role.kubernetes.io/odf` adalah
selector `Exists`, jadi cocok tanpa `=true`. Untuk `matchExpressions` pakai
`operator: Exists`; jangan mengarang label `=true` hanya agar `In` cocok.

Toleration yang dibutuhkan pod di node odf:

```yaml
tolerations:
  - key: node.ocs.openshift.io/storage
    operator: Equal
    value: "true"
    effect: NoSchedule
```

`value: "true"` **wajib dikutip**. Tanpa kutip, YAML membacanya sebagai boolean
dan API server menolak:

```text
cannot unmarshal bool into Go struct field Toleration.spec.tolerations.value of type string
```

## Jangan pasang `openshift.io/node-selector` di namespace ODF

Anotasi namespace dibaca plugin admission `PodNodeSelector` saat pod dibuat,
lalu digabung ke `spec.nodeSelector` pod. Masalahnya: anotasi ini juga
memengaruhi **DaemonSet**. OpenShift mem-patch DaemonSet controller
(`pkg/controller/daemon/daemon_controller.go`) agar `openshift.io/node-selector`
namespace ikut menentukan node target, bukan hanya pod.

Terbukti dengan DaemonSet probe identik:

| Anotasi namespace | `desired` |
| --- | --- |
| (tanpa) | 2 |
| `node-selector: kubernetes.io/os=linux` | 2 |
| `node-selector: node-role.kubernetes.io/odf=` | **0** |
| `node-selector: nonexistent=yes` | **0** |

Karena itu `odf/ns.yaml` memasang `openshift.io/node-selector: ''` (kosong =
tidak menyuntik apa pun). `defaultTolerations` juga tidak dipakai: taint node
odf sudah ditoleransi bawaan ODF dan toleration hardcoded CSI.

## Urutan deploy

```sh
# 1. Node odf: MachineSet memasang label + taint
oc apply -f compute/machineSets/odf.yaml

# 2. LSO
oc apply -f storage/local-volume/ns.yaml
oc annotate namespace openshift-local-storage openshift.io/node-selector='' --overwrite
# install LSO via OperatorHub, lalu:
oc apply -f storage/local-volume/lvd.yaml
oc apply -f storage/local-volume/lvs.yaml

# 3. ODF
oc apply -f storage/odf/ns.yaml
# install ODF via OperatorHub, lalu:
oc apply -f storage/odf/storageCluster.yaml
```

`openshift-local-storage` memakai `node-selector: ''` karena namespace itu
**tidak** perlu pinning — DaemonSet LSO sudah dipin lewat `nodeSelector` di
CR-nya, dan anotasi namespace hanya akan mengganggu.

### Mengubah taint pada cluster yang sudah jalan

Taint tersimpan di **tiga lapis**. Mengubah hanya salah satu tidak cukup —
controller mengembalikannya dari lapis di atasnya. Urutannya:

```sh
# a. MachineSet (sumber kebenaran untuk node baru)
oc apply -f compute/machineSets/odf.yaml

# b. Machine yang sudah ada (tanpa ini, node dikembalikan ke taint lama)
oc get machine.machine.openshift.io -n openshift-machine-api \
  -l machine.openshift.io/cluster-api-machineset=hub-m8sgg-odf-ap-southeast-1a \
  -o name | while read m; do
    oc patch "$m" -n openshift-machine-api --type json \
      -p '[{"op":"replace","path":"/spec/taints","value":[{"key":"node.ocs.openshift.io/storage","value":"true","effect":"NoSchedule"}]}]'
  done

# c. Node itu sendiri
for n in $(oc get nodes -l node-role.kubernetes.io/odf -o name); do
  oc adm taint node "$n" odf=node:NoSchedule- 2>/dev/null
  oc adm taint node "$n" odf=node:NoExecute- 2>/dev/null
done
```

Catatan: `oc get machineset` butuh API group eksplisit di cluster ini —
`oc get machineset.machine.openshift.io`.

## Nilai yang harus cocok

| Tempat | Nilai | Catatan |
| --- | --- | --- |
| `lvs.yaml` `storageClassName` | `lvs-sc` | dibuat otomatis oleh LSO |
| `storageCluster.yaml` `dataPVCTemplate.storageClassName` | `lvs-sc` | harus sama |
| `storageCluster.yaml` `dataPVCTemplate...storage` | `300Gi` | **harus** sama dengan kapasitas PV; `1` berarti 1 byte |
| `lvs.yaml` `minSize` | `100G` | disk 300Gi lolos filter |

`storage: 1` tetap bisa bind selama semua PV berukuran sama (Kubernetes memilih
PV terkecil yang mencukupi), tapi rapuh begitu ada PV dengan ukuran berbeda.

## Verifikasi

```sh
# LSO: semua node odf terlayani
oc get ds -n openshift-local-storage          # desired == jumlah node odf

# CSI: driver terdaftar di SETIAP node yang akan memakai volume
oc get ds -n openshift-storage                # desired == jumlah node
oc get csinode -o json | jq -r '.items[] |
  "\(.metadata.name) \(.spec.drivers[].name)"' | grep rbd

# ODF sehat
oc get cephcluster -n openshift-storage       # HEALTH_OK
oc get storagecluster -n openshift-storage    # Phase: Ready
oc get pvc -n openshift-storage               # semua Bound
```

Kalau `desired` DaemonSet CSI lebih kecil dari jumlah node, atau driver tidak
muncul di `csinode`, periksa taint node dan toleration nodeplugin — lihat bagian
di atas.
