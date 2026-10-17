# Backup

Automated etcd backup ke object storage (noobaa/ODF), adapted dari:
<https://medium.com/@arun4477/automated-etcd-backup-to-object-storage-in-openshift-4-20-886f4febb365>

Alur:

```
CronJob etcd-backup (ns etcd-backup, 01:00 WIB)
  -> oc debug node/<master> -- chroot /host /usr/local/bin/cluster-backup.sh <dir>
  -> tar czf (stream file backup dari node)
  -> aws s3 cp ke s3://<bucket noobaa> (TLS via CA bundle, bukan --no-verify-ssl)
  -> cleanup dir di node + tar lokal
```

## Komponen

| File | Isi |
|---|---|
| `namespace.yaml` | ns `etcd-backup` |
| `serviceAccount.yaml` | SA `etcd-backup-sa` |
| `rbac.yaml` | ClusterRole + ClusterRoleBinding `cluster-etcd-backup` (nodes get/list; pods+log CRUD utk `oc debug`) — nama SA/ns artikel ada typo `openshift-backup`/`ocp-etcd-backup`, sudah dinormalisasi |
| `obc.yaml` | OBC `etcd-backup-s3` di `openshift-storage` (pattern sama dgn logging/thanos) |
| `buildConfig.yaml` | ImageStream + BuildConfig `ose-cli-aws` (ose-cli + awscli v2 + openssh-clients, build in-cluster) |
| `cronjob.yaml` | CronJob `etcd-backup` → bucket S3 harian 01:00 WIB |
| `cronjob-bastion.yaml` | CronJob `etcd-backup-bastion` → bastion `ubuntu@13.215.179.173:/opt/etcd-backup` harian 00:00 WIB |
| `retention-cronjob.yaml` | CronJob `etcd-backup-retention` harian 02:15 WIB — hapus backup > **14 hari** di **bucket S3** (parsing tanggal key, epoch-based) |
| `retention-cronjob-bastion.yaml` | CronJob `etcd-backup-retention-bastion` harian 02:30 WIB — hapus backup > **14 hari** di **bastion** (`find -mmin`) — PISAH, belum di-apply (live masih cronjob gabungan `etcd-backup-retention` 02:15) |

Skrip `cluster-backup.sh` dibawakan node master (hasil installer OCP), isi = snapshot etcd + resource static pod.

**Bastion (lapis kedua):** `ubuntu@13.215.179.173` (ip-10-137-230-7), dir `/opt/etcd-backup`
(sudah dibuat, owned ubuntu). Auth dedicated keypair ed25519 passphraseless `ocp-etcd-backup`:
- private key tersimpan di Mesin: Fajar: `~/.ssh/etcd-backup-key`
- public key terdaftar di `~/.ssh/authorized_keys` bastion
- ke cluster masuk sebagai Secret `etcd-backup-bastion-ssh` (key `id_ed25519`) — langkah 5b di bawah
- egress pod → bastion `13.215.179.173:22` harus diboleh SG bastion (inbound 22 dari egress IP NAT cluster)

## Urutan apply

```bash
# 1. bucket
oc apply -f obc.yaml
oc get obc etcd-backup-s3 -n openshift-storage        # tunggu BOUND
oc get obc etcd-backup-s3 -n openshift-storage -o jsonpath='{.spec.bucketName}'

# 2. ns + SA + RBAC + buildConfig
oc apply -f namespace.yaml
oc apply -f serviceAccount.yaml
oc apply -f rbac.yaml
oc apply -f buildConfig.yaml

# 3. SCC privileged untuk SA (bermata pod debug jalan root di host)
oc adm policy add-scc-to-user privileged -z etcd-backup-sa -n etcd-backup

# 4. build image (butuh egress ke registry.redhat.io + awscli.amazonaws.com)
oc start-build ose-cli-aws -n etcd-backup --follow

# 4b. (opsional setelah test) retensi 14 hari dijalankan cronjob terpisah:
#     harian 02:15 — bersihkan bucket S3 (parler parsing tanggal di key)
#     + bastion (find -mtime). Kebutuhan best practice: 7-14 harian rutin,
#     compliant pakai GFS (7 harian/4 mingguan/12 bulanan).
#     Retensi test-mode bisa dipicu manual:
# oc create job --from=cronjob/etcd-backup-retention etcd-backup-retention-manual -n etcd-backup

# 5. secret kredensial dari OBC + secret CA noobaa (signing-key/service-ca, sama dgn sisi loki/thanos)
oc apply -f - <<EOF
kind: Secret
apiVersion: v1
metadata:
  name: etcd-backup-s3-creds
  namespace: etcd-backup
stringData:
  AWS_ACCESS_KEY_ID: $(oc get secret etcd-backup-s3 -n openshift-storage -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
  AWS_SECRET_ACCESS_KEY: $(oc get secret etcd-backup-s3 -n openshift-storage -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)
EOF
oc get secret signing-key -n openshift-service-ca -o jsonpath='{.data.tls\.crt}' | base64 -d \
  | oc create secret generic etcd-s3-ca -n etcd-backup --from-file=ca.crt=/dev/stdin

# 5b. secret SSH key bastion (dari ~/.ssh/etcd-backup-key Mac)
oc create secret generic etcd-backup-bastion-ssh -n etcd-backup \
  --from-file=id_ed25519=$HOME/.ssh/etcd-backup-key

# 6. isi nama bucket di cronjob.yaml (S3_BUCKET), apply, aktifkan
oc apply -f cronjob.yaml -n etcd-backup
oc apply -f cronjob-bastion.yaml -n etcd-backup
oc patch cronjob etcd-backup -n etcd-backup -p '{"spec":{"suspend":false}}'
oc patch cronjob etcd-backup-bastion -n etcd-backup -p '{"spec":{"suspend":false}}'
```

## Test manual

```bash
# ke bucket S3
oc create job --from=cronjob/etcd-backup etcd-backup-manual -n etcd-backup
oc logs -f -n etcd-backup job/etcd-backup-manual

# ke bastion (butuh SG bastion allow inbound 22 dari egress cluster)
oc create job --from=cronjob/etcd-backup-bastion etcd-backup-bastion-manual -n etcd-backup
oc logs -f -n etcd-backup job/etcd-backup-bastion-manual
```

Hasilnya `backup-<DATE>.tar.gz` di bucket S3 dan/atau `/opt/etcd-backup` bastion; restore OCP dokumentasi resmi "Restoring a valid cluster from an etcd backup".
