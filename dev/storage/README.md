# Huawei Storage (Dorado, assumed) — dev

CSI driver resmi: `Huawei/eSDK_K8S_Plugin` v4.13.0, Helm chart `helm/esdk`,
driver `csi.huawei.com`, ns `huawei-csi`. Bukan OLM — install via Helm.

> Asumsi model = Dorado. Kalau ternyata Pacific/FusionStorage, ganti
> `storage:` di `11-backend-configmap.yaml` + `provider:` di
> `12-backend-claim.yaml`. Protocol = FC (zoning host↔storage wajib ada).

## Urutan deploy

```sh
K=dev/dev.kubeconfig
# 0. Isi placeholder <ISI_...> di 10 + 11 (JANGAN commit nilai asli)

# 1. CSI driver via Helm (CRD backend ikut dari chart)
helm install huawei-csi oci://<registry>/esdk --version 4.13.0 \
  -n huawei-csi --create-namespace -f 00-helm-values.yaml

# 2. Backend: Secret + ConfigMap + Claim
kubectl --kubeconfig=$K apply -f 10-backend-secret.yaml \
  -f 11-backend-configmap.yaml -f 12-backend-claim.yaml

# 3. Konsumsi: StorageClass + SnapshotClass
kubectl --kubeconfig=$K apply -f 20-storageclass.yaml
```

| File | Isi |
| --- | --- |
| `00-helm-values.yaml` | override chart: controller 2 replika, snapshot+resizer on, toleration master, CSIDriverObject create |
| `10-backend-secret.yaml` | kredensial DeviceManager (placeholder) |
| `11-backend-configmap.yaml` | URL DM + pool + portal iSCSI (placeholder) |
| `12-backend-claim.yaml` | StorageBackendClaim `dorado-dev` → Secret+CM |
| `20-storageclass.yaml` | SC `huawei-dorado-block` (LUN/RWO, untuk VM) + `huawei-dorado-file` (NFS/RWX) + VSC |

## Verifikasi

```sh
K=dev/dev.kubeconfig
kubectl --kubeconfig=$K get sbc -n huawei-csi                    # STATUS Bound/Available
kubectl --kubeconfig=$K get csidriver csi.huawei.com             # ada
kubectl --kubeconfig=$K get sc \| grep huawei                     # 2 SC
# smoke: PVC 1Gi dari huawei-dorado-block harus Bound
kubectl --kubeconfig=$K apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: huawei-smoke
  namespace: default
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: huawei-dorado-block
  resources: {requests: {storage: 1Gi}}
EOF
```

## Catatan

- `hub/policies/huawei-csi.yaml` (ACM, inform) cek driver terpasang —
  placeholder CSIDriver `csi.huawei.com` di sana sekarang **confirmed benar**.
  Nama Deployment/DaemonSet di policy itu masih placeholder: sesuaikan dengan
  nama real dari Helm chart setelah install (`huawei-csi-controller` /
  `huawei-csi-node` vs aktual).
- FC: pastikan zoning host↔storage + HBA multipath di node (multipathd).
  iSCSI (kalau nanti dipakai): `storage: oceanstor-iscsi` + `portals:` di
  backend config. NAS (dtree): contoh di
  `examples/backend/backend-dtree.yaml` upstream.
- CNV VM disk RWO tidak butuh multipath di dalam guest.
