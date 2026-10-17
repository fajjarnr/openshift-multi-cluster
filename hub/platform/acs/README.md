# RHACS (Advanced Cluster Security)

Urutan apply:

```sh
oc apply -f ns.yaml
oc apply -f adminPassword.yaml
oc apply -f central.yaml
# tunggu Central Available=True, lalu generate CRS (lihat bawah)
oc apply -f hub-cluster-registration-secret.yaml
oc apply -f secured.yaml
```

`secured.yaml` **tidak akan jalan** tanpa CRS. Kalau belum ada, SecuredCluster
melaporkan:

```text
Irreconcilable=True  ReconcileError: some init-bundle secrets missing in
namespace "stackrox", please make sure you have downloaded init-bundle secrets
(from UI or with roxctl) and created corresponding resources in the correct namespace
```

## Generate CRS lewat CLI

CRS (Cluster Registration Secret) lebih disarankan daripada init bundle
(docs RHACS 4.11 §1.4.2): CRS berisi token sekali pakai, bukan sertifikat
berumur 1 tahun, dan bisa dicabut langsung setelah instalasi tanpa memutus
koneksi cluster.

```sh
# 1. roxctl — ambil dari mirror Red Hat, bukan dari Central
#    Endpoint /api/cli/<os>/roxctl di cluster ini mengembalikan HTML SPA
#    (route reencrypt + Redirect), bukan binary.
curl -sL -o /usr/local/bin/roxctl \
  https://mirror.openshift.com/pub/rhacs/assets/4.11.5/bin/Darwin/roxctl
chmod +x /usr/local/bin/roxctl
roxctl version

# 2. API token (sekali saja, lewat UI)
#    Central UI -> Platform Configuration -> Integrations ->
#    Authentication Tokens -> API Token, role: Admin
export ROX_API_TOKEN=<token>
export ROX_CENTRAL_ADDRESS=central-reencrypt-stackrox.apps.hub.ocp.fajjjar.my.id:443

# 3. Generate
roxctl -e "$ROX_CENTRAL_ADDRESS" \
  central crs generate hub-cluster \
  --output hub-cluster-registration-secret.yaml
```

Flag lain yang tersedia:

| Flag | Keterangan |
| --- | --- |
| `--max-clusters=0` | batasi jumlah cluster yang boleh register (0 = tanpa batas) |
| `--valid-for` | durasi validitas, mis. `10m`, `1d` |
| `--valid-until` | RFC3339 timestamp |
| `-o, --output` | file output, `-` untuk stdout |

Kelola CRS tanpa UI:

```sh
roxctl -e "$ROX_CENTRAL_ADDRESS" central crs list
roxctl -e "$ROX_CENTRAL_ADDRESS" central crs revoke <crs_name>
```

Alternatif lama (init bundle), masih didukung:

```sh
roxctl -e "$ROX_CENTRAL_ADDRESS" \
  central init-bundles generate hub-cluster --output-secrets \
  hub-cluster-init-bundle.yaml
```

## Secret yang tidak boleh di-commit

File secret kini memakai **placeholder** (aman untuk repo publik):

- `hub-cluster-registration-secret.yaml` → `crs: <ISI_CRS_BASE64_DARI_CENTRAL>`
- `adminPassword.yaml` → `password: <ISI_PASSWORD_ADMIN>`

Isi nilai aslinya sebelum `oc apply` (lihat komentar di masing-masing file).
Nilai asli tetap TIDAK boleh masuk git — kalau tidak sengaja ter-commit,
ganti/rotate kredensialnya, bukan hanya hapus file.

## Penempatan pod

`customize.deploymentDefaults.nodeSelector: node-role.kubernetes.io/infra-opp: ""`
di `central.yaml` dan `secured.yaml` memindahkan komponen **Deployment**
(Central, Scanner, Sensor, Admission Control) ke node infra-opp.

Yang **tidak** terpengaruh:

- **Collector** — DaemonSet, tetap di semua node (memang harus, ia mengumpulkan
  aktivitas tingkat host). Toleransinya `operator: Exists`.
- **ScannerV4** — komponennya punya `nodeSelector` sendiri di
  `spec.scannerV4.<db|indexer|matcher>.nodeSelector`, yang **menimpa**
  `deploymentDefaults`.

### `pinToNodes: InfraRole` tidak dipakai

Enum-nya hanya `None`/`InfraRole`, dan `InfraRole` di-hardcode
(`operator/api/v1alpha1/common_types.go`) ke:

```go
NodeSelector: {"node-role.kubernetes.io/infra": ""}
Tolerations:  [{key: node-role.kubernetes.io/infra, value: "reserved", effect: NoSchedule},
               {key: node-role.kubernetes.io/infra, value: "reserved", effect: NoExecute}]
```

Cluster ini memakai label `node-role.kubernetes.io/infra-opp` tanpa taint, jadi
`InfraRole` akan salah menempatkan pod ke node `infra` dan toleransinya tidak
match. CRD juga melarang `pinToNodes` digabung dengan
`nodeSelector`/`tolerations`.

## Route dan TLS

`central.yaml` memakai `exposure.route.reencrypt.enabled: true`, bukan
passthrough. Passthrough meneruskan TLS mentah ke Central sehingga browser
melihat cert self-signed internal Central.

`reencrypt.tls` sengaja **tidak diisi** — semua field-nya opsional dan
default-nya cert OpenShift CA. Router sudah menyajikan wildcard
`*.apps.hub.ocp.fajjjar.my.id` dari cert-manager
(`cert-manager/4-certificate.apps.yaml` → secret `app-router-certs` →
`defaultCertificate` IngressController), jadi host Central sudah tercakup.

cert-manager **tidak bisa** diintegrasikan langsung: `reencrypt.tls` hanya
menerima string PEM inline (`certificate`, `key`, `caCertificate`,
`destinationCACertificate`) — tidak ada `secretRef`.

## ScannerV4

Field-nya di **`spec.scannerV4`** (top-level), bukan `spec.scanner.scannerV4`.
`spec.scanner` adalah Scanner v2 — keduanya bisa jalan bersamaan.

```yaml
scannerV4:
  scannerComponent: Enabled      # enum: Default, Enabled, Disabled
  db:
    persistence:
      persistentVolumeClaim:
        claimName: scanner-v4-db
        size: 50Gi
        storageClassName: ocs-storagecluster-ceph-rbd
```

Kalau `db.persistence` tidak diisi, ia memakai `emptyDir` — data hilang saat pod
restart.

Defaulting dari CRD: untuk instalasi baru sejak ACS 4.8, ScannerV4 default
`Enabled`. Untuk upgrade dari versi sebelumnya, default `Disabled`.

## Verifikasi

```sh
oc get central,securedcluster -n stackrox     # keduanya Available=True
oc get pods -n stackrox                       # semua Running
oc get pvc -n stackrox                        # semua Bound
oc get route -n stackrox                      # central-reencrypt
```

`scanner-db` (Scanner v2) bisa tampak `Pending` lama saat pertama kali — itu
`init-db` sedang mengimpor data kerentanan (tabel `vuln_v2`, ratusan ribu baris).
Bukan macet; cek progres dengan:

```sh
oc logs scanner-db-<hash> -n stackrox -c init-db --tail=20
```
