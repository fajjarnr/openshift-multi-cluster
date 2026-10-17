# Multi-Cluster OpenShift + RHACM Lab (Hub & Development)

Repositori manifest klaster OpenShift + RHACM, dengan IaC AWS.
Infrastruktur: **[terraform/README.md](terraform/README.md)** — 2 VPC + 2 bastion + VPC peering + ODF raw disks (9×300GiB).

## Struktur repo

```
terraform/             # IaC AWS: VPC hub+dev, bastion, DNS, EBS disk ODF (README lengkap di sini)
hub/                   # Manifest cluster HUB (OpenShift + RHACM)
├── backup/            # etcd backup → S3 noobaa & bastion + retensi 14 hari (README lengkap)
├── compute/           # machineSets, machineConfigPool, machineConfig
├── custom-resource/   # CR apps: ingress, logging, monitoring, registry
├── operator/          # operator CR (cert-manager)
├── platform/          # platform vendor: ACM (MCH/MCO), ACS (central), gitops
├── policies/          # RHACM policies
└── storage/           # ODF + local-volume (LVD/LVS untuk raw disk EBS)
development/           # manifest cluster DEV
```

## Cluster

| Cluster | API | Catatan |
| --- | --- | --- |
| **hub** | `api.hub.ocp.fajjjar.my.id:6443` | 3 master + 3 infra + 3 odf + infra-opp; ODF; ACM 2.x; ACS 4.x |
| **development** | — | cluster kedua di VPC dev, disambung via VPC peering |

Infrastruktur: 2 VPC `ap-southeast-1` (`10.137.230.0/25` hub, `10.137.230.128/25` dev), VPC peering dua arah, S3 gateway endpoint, bastion masing-masing VPC. Deployment bertahap via `enable_hub`/`enable_dev` (simp 2 terraform/README.md).

## Komponen utama cluster hub

| Komponen | Manifest | Status |
| --- | --- | --- |
| ACM MCH (multiclusterhub) | `hub/platform/acm/multiclusterhub.yaml` | ✓ jalan |
| ACM MCO (observability thanos, PVC di infra-opp) | `hub/platform/acm/multiclusterobservability.yaml` | ✓ Ready=True |
| ACS central | `hub/platform/acs/central.yaml` | ✓ Running |
| Registry (image-registry ke cephfs) | `hub/custom-resource/registry/` | ✓ 3/3 |
| Logging (Loki + CLF) | `hub/custom-resource/logging/` | config final, apply parsiel |
| ODF raw disks / LSO | `hub/storage/local-volume/` (lvd/lvs) + `terraform/04-ebs-odf.tf` | LSO config siap; 9 disk dibuat tf (attach manual) |
| etcd backup 2 jalur (bucket noobaa + bastion) + retensi 14 hari | `hub/backup/` | ✓ 3 cronjob aktif |

## Catatan

- Secret berisi kredensial disimpan dalam file ini secara sengaja (repo privat) — ikuti pola `stringData` + placeholder
- Retensi backup = sliding window "keep 14 hari" via `RETENTION_MINUTES=20160` di `hub/backup/retention-cronjob*.yaml`
- Bastion backup offsite: `ubuntu@13.215.179.173:/opt/etcd-backup` (SSH key dedicated `~/.ssh/etcd-backup-key`)
- Repo ini bukan git repo aktif — `.gitignore` di `terraform/` melindungi tfstate; state jangan di-commit
