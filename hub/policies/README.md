# ACM Governance Policies

Policy di direktori ini tinggal di hub (`open-cluster-management` 2.17.3) dan
didistribusikan ke managed cluster lewat Placement.

```sh
kubectl --kubeconfig=hub/hub.kubeconfig apply -f compliance-operator.yaml
```

## `external-secrets-operator.yaml`

Req: External Secrets Operator terpasang di cluster yang pakai Vault, mode
**enforce**. OperatorPolicy (`openshift-external-secrets-operator`, channel
`stable-v1` (= v1.2.1), dari `redhat-operators`, ke ns
`openshift-external-secrets`, AllNamespaces-only) + ConfigurationPolicy cek
CSV `Succeeded`.

Pakai build Red Hat (`openshift-external-secrets-operator`), bukan
`external-secrets-operator` community (v0.11.0, default channel `alpha`).
Placement opt-in via label `secrets=vault` — saat ini hanya dev. Hub tidak
kena (ns tidak ada di hub, terverifikasi).

## `logging-operators.yaml` + `log-forwarding.yaml`

Req: log-forwarding ke LokiStack ada di semua cluster, mode **enforce**.
Dua file karena ConfigurationPolicy tidak bisa install operator (CRD belum
ada = template gagal):

1. **`logging-operators.yaml`** — 2× OperatorPolicy: `cluster-logging` +
   `loki-operator`, channel `stable-6.6` (default terverifikasi), target
   `vendor=OpenShift` (hub+dev). CLO ke `openshift-logging`, Loki ke
   `openshift-operators-redhat` (AllNamespaces-only).
2. **`log-forwarding.yaml`** — ConfigurationPolicy enforce, spec disalin dari
   `hub/cluster-config/logging/`:
   - `logging-collector-rbac`: SA `logging-collector` + 4 ClusterRoleBinding
     (ClusterRole dibuat CLO)
   - `cluster-log-forwarder`: CLF `instance`, pipeline all-logs
     (application+infrastructure+audit → lokistack-out). Tolerations
     infra/ODF dari yaml hub di-strip (tidak ada di test cluster).

## `lokistack-prod.yaml` — DISABLED, jangan apply di hub/dev

LokiStack `logging-loki` (ODF, `storageClassName:
ocs-storagecluster-ceph-rbd`, Secret S3 `logging-loki-secret` exists-check).
Root `disabled: true` + Placement `storage=odf`: test cluster sengaja tidak
deploy LokiStack (hemat cost node infra + butuh ODF). Enable hanya di cluster
prod (`disabled: false` + label `storage=odf` + Secret S3 valid dari OBC
NooBaa).

Gotcha:

- `disabled` hanya ada di root `Policy.spec`, **bukan** di ConfigurationPolicy
  (`spec.disabled` → template-error strict decoding). Itu sebabnya LokiStack
  jadi file/policy terpisah, bukan template ke-3.
- CLO cache RBAC stale: setelah ClusterRoleBinding dibuat policy, CLF dev
  sempat `Authorized=False/ClusterRoleMissing` padahal binding identik dengan
  hub (yang langsung Ready). Sembuh dengan re-trigger reconcile (annotate +
  hapus annotate). Kalau ketemu lagi: annotate CLF apa saja lalu hapus —
  enforce jaga spec tetap sesuai yaml.

## `netpol-baseline.yaml`

Req: baseline NetworkPolicy ada di namespace workload tertentu, mode
**enforce**. Satu ConfigurationPolicy dengan `namespaceSelector` opt-in
(`netpol-baseline=enabled`) — namespace baru tidak otomatis kena. Placement
exclude hub (management plane), jadi cuma dev (+ managed cluster baru).

Isi `baseline-default` (2b: deny-ingress + allow DNS/egress):

- ingress: hanya dari pod dalam namespace yang sama
- egress: ke pod DNS `openshift-dns` + ke pod dalam namespace yang sama
- akses lintas namespace butuh NetworkPolicy allow eksplisit

Label namespace workload baru dengan:

```sh
oc label namespace <nama> netpol-baseline=enabled
```

Gotcha OVN-K (terbukti via smoke test): Service DNS `172.31.0.10:53` di-DNAT
ke pod port **5353** (lihat EndpointSlice), dan egress NP dievaluasi
post-DNAT — rule harus pakai 5353, port 53 tidak pernah match. Test: DNS
resolve OK, wget cross-namespace timeout (blocked), same-namespace refused
(allowed, cuma tidak ada server).

Catatan `musthave`: merge, bukan replace — field/rule yang dihapus dari yaml
tidak ikut terhapus di cluster (terbukti: rule port 53 lama bertahan sampai
NP di-delete manual dan di-recreate enforce). Kalau mengubah isi NP, delete
dulu NP di managed cluster atau pakai `MustOnlyHave`.

Kenapa bukan ANP/BANP: API `v1alpha1` diserve tapi OVN-K tidak menjalankan
ANP controller (flag tidak ada) — cluster-wide policy tidak di-enforce.

## `etcd-encryption.yaml`

Req: enkripsi etcd nyala di semua self-managed OCP, **inform**
("Controlled Remediation"). ConfigurationPolicy `musthave` cek
`APIServer/cluster` dengan `spec.encryption.type: aescbc`, target
`vendor=OpenShift` (hub ikut — ia juga menyimpan secret di etcd sendiri).

Kenapa inform, bukan enforce: menyalakan enkripsi me-re-encrypt semua
secret/configmap + rolling restart kube-apiserver (API down sesaat di
SingleReplica seperti dev). Tidak boleh ke-trigger otomatis oleh controller.
Alur remediate: policy lapor NonCompliant → admin jadwalin maintenance →
enable manual per cluster:

```sh
oc patch apiserver cluster --type=merge -p '{"spec":{"encryption":{"type":"aescbc"}}}'
# tunggu migrasi selesai, lalu policy jadi Compliant sendiri:
oc get co kube-apiserver   # Progressing=False
```

Status saat dibuat: NonCompliant di hub + dev (belum ada yang enable) —
disengaja, dan inform terbukti tidak menulis apa pun ke APIServer.

## `gitops-operator.yaml`

Req: OpenShift GitOps Operator terpasang di cluster GitOps-enabled, mode
**enforce**. OperatorPolicy (`openshift-gitops-operator`, channel `latest`
(= v1.22.2), dari `redhat-operators`, ke ns `openshift-gitops-operator`,
AllNamespaces-only) + ConfigurationPolicy cek CSV `Succeeded`.

Placement opt-in via label `gitops=enabled` — bukan `vendor=OpenShift` polos,
supaya cluster yang belum siap GitOps tidak ikut. **Hub ikut dilabel**:
ApplicationSet push model butuh operator di hub (ArgoCD control plane, CRD
`applicationsets.argoproj.io`), sementara managed cluster butuh operatornya
untuk ArgoCD agent/kluster tujuan. Label cluster baru dengan:

```sh
kubectl --kubeconfig=hub/hub.kubeconfig label managedcluster <nama> gitops=enabled
```

## `nmstate-operator.yaml`

Req: NMState Operator terpasang di managed OCP cluster, mode **enforce**.
Pola identik dengan `compliance-operator.yaml`: OperatorPolicy
(`kubernetes-nmstate-operator`, channel `stable`, dari `redhat-operators`, ke
ns `openshift-nmstate`, CSV `4.22.0-202610241757`) + ConfigurationPolicy cek CSV
`Succeeded`. Namespace `policies` dan ManagedClusterSetBinding tidak diulang
(sudah ada dari file compliance).

Beda dari compliance: Placement **exclude hub** (`matchExpressions:
local-cluster NotIn [true]`) — NMState hanya untuk managed cluster yang butuh
network config deklaratif (rencana: OpenShift Virtualization di dev). Hub tidak
butuh: network-nya default CNI cukup. Managed cluster baru otomatis tercakup
tanpa label manual.

Catatan unplace: Governance tidak menghapus operator saat cluster keluar dari
Placement — NMState yang sempat terinstall di hub di-uninstall manual
(Subscription → CSV → namespace → CRD `nmstates.nmstate.io`).

## `compliance-operator.yaml`

Req: Compliance Operator harus terpasang di semua managed OCP cluster, mode
**enforce**. Isinya 5 resource dalam satu file:

| Resource | Fungsi |
| --- | --- |
| `Namespace/policies` | wadah semua object policy di hub |
| `ManagedClusterSetBinding/default` | bind clusterset `default` ke ns `policies` — tanpa ini Placement tidak bisa memilih cluster dari set tersebut |
| `Policy/compliance-operator` | root policy: 2 template (OperatorPolicy + ConfigurationPolicy) |
| `Placement/compliance-operator` | pilih target: semua cluster berlabel `vendor=OpenShift` |
| `PlacementBinding` | ikat Policy ↔ Placement, sehingga policy direplikasi ke cluster terpilih |

Alur propagasi: root Policy di ns `policies` → direplikasi ke ns
`<cluster-name>` di hub (mis. `policies.compliance-operator` di ns `dev`) →
didistribusikan ke managed cluster oleh governance-policy-framework addon.

## `remediationAction`

Ada 2 nilai: `inform` (default) dan `enforce`.

- `inform` — hanya lapor. Policy yang tidak compliant tetap dibiarkan, statusnya
  `NonCompliant` di console/CLI. Dipakai untuk audit atau rollout bertahap.
- `enforce` — controller **memperbaiki otomatis**: object yang hilang dibuat,
  yang drift dikembalikan ke definisi policy.

Precedence: `remediationAction` di root `Policy.spec` **menimpa** nilai di semua
child template (`policy-templates`). Di file ini ketiganya diset `enforce`
eksplisit supaya terbaca jelas tanpa harus ingat aturan override.

Field terkait yang juga mengontrol perilaku:

- `disabled: false` — kalau `true`, policy dicabut dari semua managed cluster.
- `complianceType: musthave` — state yang diinginkan: operator/object harus ada
  (lawan: `mustnothave`). Ini yang dibandingkan controller untuk menentukan
  Compliant/NonCompliant.
- `severity: high` — label keparahan saat NonCompliant (`low`/`medium`/`high`/
  `critical`); tampil di console, tidak mengubah perilaku remediate.
- `upgradeApproval: Automatic` — khusus OperatorPolicy: InstallPlan upgrade
  operator di-approve otomatis. Kalau `None`, upgrade nunggu approval manual di
  tiap managed cluster.

## Template 1: OperatorPolicy `install-compliance-operator`

Mendeklarasikan Subscription yang diinginkan (`compliance-operator`, channel
`stable`, dari `redhat-operators`, ke ns `openshift-compliance`). Controller
membuat Namespace, OperatorGroup (AllNamespaces), dan Subscription kalau belum
ada — lalu memantau kesehatan install (Subscription, InstallPlan, CSV,
Deployment, CRD, CatalogSource) sebagai satu compliance.

Catatan: `installPlanApproval` **dilarang** di `spec.subscription` OperatorPolicy
(diatur lewat `upgradeApproval`) — policy ditolak sebagai `InvalidPolicySpec`
kalau diisi. Pelajaran dari apply pertama file ini.

## Template 2: ConfigurationPolicy `compliance-operator-healthy`

Check generik: minimal satu ClusterServiceVersion di ns `openshift-compliance`
harus berstatus `Succeeded`, diseleksi via label OLM standar
`operators.coreos.com/compliance-operator.openshift-compliance`. Tanpa `metadata.name`,
`objectSelector` memilih semua CSV berlabel itu; `musthave` terpenuhi kalau
≥1 match dan statusnya sesuai.

Kenapa dua template: OperatorPolicy sudah mencakup cek CSV, tapi template ini
menangkap skenario drift yang OperatorPolicy anggap compliant — mis. CSV lama
`Succeeded` masih ada sementara upgrade macet. Duplikasi yang disengaja, murah.

## `odf-operator.yaml` — JANGAN APPLY di hub/dev

Req: ODF Operator terpasang di managed cluster produksi (ODF internal mode),
mode **enforce**. Cluster test (hub/dev) tidak punya node ODF/disk, jadi
Placement menarget label manual `storage=odf`, bukan `vendor=OpenShift`.

Label cluster produksi sebelum apply:

```sh
kubectl --kubeconfig=hub/hub.kubeconfig label managedcluster <nama> storage=odf
```

Template 1 — OperatorPolicy `install-odf-operator`: Subscription `odf-operator`
channel `stable-4.22` (default channel di katalog, CSV `odf-operator.v4.22.6-rhodf`),
dari `redhat-operators`, ke ns `openshift-storage`. Beda dari Compliance:
`operatorGroup` diisi eksplisit dengan `targetNamespaces: [openshift-storage]`
karena CSV ODF hanya support `OwnNamespace`/`SingleNamespace` — default
controller (`AllNamespaces`) akan bikin install gagal.

Template 2 — ConfigurationPolicy `odf-storagecluster-ready`, mode **inform**:
StorageCluster `ocs-storagecluster` harus `phase: Ready`. Sengaja inform, bukan
enforce: StorageCluster butuh disk/node ODF yang tidak bisa dibuat otomatis —
kalau di-enforce, controller akan mencoba create CR yang tidak akan pernah Ready.

## `huawei-csi.yaml` — JANGAN APPLY di hub/dev

Req: Huawei CSI driver terpasang di managed cluster produksi yang memakai
storage Huawei (OceanStor/Dorado on-prem). **Seluruh policy mode inform** —
verifikasi saja, bukan instalasi. Alasannya:

- Huawei CSI on-prem **tidak ada di OperatorHub** (dicek: tidak ada di
  redhat-, certified-, maupun community-operators) — instalasi via Helm chart /
  manifest dari paket dukungan Huawei, jadi tidak bisa di-enforce via
  OperatorPolicy.
- Satu-satunya Huawei CSI publik adalah `huaweicloud/huaweicloud-csi-driver`
  (EVS/SFS/OBS untuk Huawei Cloud, install via `kubectl apply` manifest mentah
  ke `kube-system`, driver `evs.csi.huaweicloud.com`) — bukan untuk on-prem
  OceanStor dan bukan OLM. Docs enterprise Huawei (`support.huawei.com`) tidak
  bisa diakses tanpa akun.

Tiga check ConfigurationPolicy (sesuaikan nama/namespace dengan instalasi real
sebelum pakai — nilai di file ini placeholder dari pola umum chart CSI):

| Check | Object | Kriteria |
| --- | --- | --- |
| driver terdaftar | `CSIDriver/csi.huawei.com` | `attachRequired: true` |
| controller sehat | `Deployment/huawei-csi-controller` ns `huawei-csi` | `availableReplicas: 1` |
| node plugin sehat | `DaemonSet/huawei-csi-node` ns `huawei-csi` | `numberUnavailable: 0` |

Placement menarget label manual `storage=huawei` (lihat pola `storage=odf` di
atas). Kalau nanti Huawei merilis operator OLM/certified, ganti template 1
dengan OperatorPolicy seperti `odf-operator.yaml`.

## Verifikasi

```sh
K=hub/hub.kubeconfig
kubectl --kubeconfig=$K get policy -n dev; kubectl --kubeconfig=$K get policy -n hub  # replika per cluster
kubectl --kubeconfig=$K get placementdecision -n policies \
  -o jsonpath='{range .items[*]}{.status.decisions[*].clusterName}{"\n"}{end}'  # dev hub
kubectl --kubeconfig=$K get policy -n dev -n hub 2>/dev/null; kubectl --kubeconfig=$K get policy -n hub  # replika per cluster
kubectl --kubeconfig=dev/dev.kubeconfig get csv -n openshift-compliance        # compliance-operator.vX Succeeded
```

Troubleshoot NonCompliant: `status.conditions` di OperatorPolicy managed
cluster menjelaskan penyebabnya (`SubscriptionMatches`, `InstallPlansInstalling`,
`RequirementsNotMet`, dst.):

```sh
kubectl --kubeconfig=dev/dev.kubeconfig get operatorpolicy install-compliance-operator -n dev \
  -o jsonpath='{range .status.conditions[*]}{.type}{"="}{.reason}{" "}{.message}{"\n"}{end}'
```
