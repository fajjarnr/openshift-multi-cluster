# Multi-Cluster OpenShift & RHACM Lab Infrastructure (2 VPCs + 2 Bastions on AWS)

Terraform infrastructure provisioning **2 separate AWS VPCs** connected via **AWS VPC Peering** with **2 Bastion Hosts** for a **Red Hat Advanced Cluster Management (RHACM)** lab:

- **Hub Cluster VPC** (`10.137.230.0/25`) + **Hub Bastion**
- **Dev Cluster VPC** (`10.137.230.128/25`) + **Dev Bastion**
- **AWS VPC Peering** (bidirectional routing between Hub and Dev)
- **Deployment Toggles** (`enable_hub` / `enable_dev`) for staged deployments

---

## 1. Multi-VPC Architecture & Subnetting Plan

Total Network Block: **`10.137.230.0/24`** (256 IPs)  
Split into **2 distinct VPCs**:

```
 ┌────────────────────────────────────────────────────────┐
 │                    AWS ap-southeast-1                  │
 │                                                        │
 │  ┌─────────────────────────┐    VPC     ┌──────────────┴──────────┐
 │  │      VPC Hub            │  PEERING   │        VPC Dev          │
 │  │  (10.137.230.0/25)      │<==========>│   (10.137.230.128/25)   │
 │  └───────────┬─────────────┘            └──────────────┬──────────┘
 │              │                                         │
 │      ┌───────┴───────┐                         ┌───────┴───────┐
 │      │               │                         │               │
 │    Public         Private                    Public         Private
 │  10.137.230.0/26  10.137.230.64/26         10.137.230.128/26 10.137.230.192/26
 │  (NLB/ALB +       (20 VMs capacity)        (NLB/ALB +        (20 VMs capacity)
 │   Hub Bastion)                              Dev Bastion)
 └────────────────────────────────────────────────────────────────────┘
```

### Subnet Details & Capacity Breakdown

| VPC         | Subnet Name               | Type    | CIDR Block          | Total IPs | Usable IPs | Target & Workloads                                       |
| :---------- | :------------------------ | :------ | :------------------ | :-------- | :--------- | :------------------------------------------------------- |
| **Hub VPC** | `...-hub-vpc-public-hub`  | Public  | `10.137.230.0/26`   | 64        | 59         | Hub External Load Balancers + **Hub Bastion**            |
| **Hub VPC** | `...-hub-vpc-private-hub` | Private | `10.137.230.64/26`  | 64        | **59**     | Hub Cluster Nodes (Master + Workers, **20 VM capacity**) |
| **Dev VPC** | `...-dev-vpc-public-dev`  | Public  | `10.137.230.128/26` | 64        | 59         | Dev External Load Balancers + **Dev Bastion**            |
| **Dev VPC** | `...-dev-vpc-private-dev` | Private | `10.137.230.192/26` | 64        | **59**     | Dev Cluster Nodes (Master + Workers, **20 VM capacity**) |

> [!NOTE]
> AWS reserves 5 IP addresses per subnet. Each private `/26` provides **59 usable host IPs**, comfortably satisfying the requirement of **20 host/VM** per cluster plus installer bootstrap and future scaling headroom.

---

## 2. Staged Deployment Workflow (Deploy Hub Dulu)

Anda dapat men-deploy infrastruktur secara bertahap menggunakan toggle variables `enable_hub` dan `enable_dev`.

### Tahap 1: Deploy Hub VPC Saja (Dev Mati)

1. Di file `terraform.tfvars`, set `enable_dev = false`:

   ```hcl
   enable_hub = true
   enable_dev = false
   ```

2. Jalankan apply:

   ```bash
   terraform apply
   ```

   _Hasil_: Hanya **VPC Hub**, Subnets Hub, Route Tables, NAT Gateway Hub, dan **Hub Bastion** yang dibuat. VPC Peering tidak aktif karena Dev belum ada.

3. Dapatkan subnet IDs untuk Hub:

   ```bash
   terraform output hub_network
   terraform output bastion_hub
   ```

4. Masukkan subnet ID ke `hub/install-config.yaml` dan install OpenShift Hub cluster.

---

### Tahap 2: Aktifkan Dev VPC & VPC Peering

Setelah cluster Hub siap dan ingin membuat cluster Dev:

1. Di file `terraform.tfvars`, ubah `enable_dev = true`:

   ```hcl
   enable_hub = true
   enable_dev = true
   ```

2. Jalankan apply:

   ```bash
   terraform apply
   ```

   _Hasil_: Terraform **tidak menyentuh/mengubah Hub yang sudah jalan**, melainkan langsung menambahkan:
   - **VPC Dev** + Subnets + NAT Gateway
   - **Dev Bastion**
   - **AWS VPC Peering Connection** antara Hub dan Dev
   - Route table routes dua arah agar node/pod Hub dan Dev bisa saling kontak.

3. Dapatkan subnet IDs untuk Dev:

   ```bash
   terraform output dev_network
   terraform output bastion_dev
   ```

4. Masukkan subnet ID ke `dev/install-config.yaml` dan install OpenShift Dev cluster.

---

## 3. Quick Reference Commands

```bash
cd terraform

# Inisialisasi
terraform init

# Validasi & Plan
terraform validate
terraform plan

# Deploy Hub only (bila di tfvars enable_dev = false) atau deploy all
terraform apply

# Cek detail output
terraform output hub_network
terraform output dev_network
terraform output bastion_hub
terraform output bastion_dev
terraform output vpc_peering_id
```

---

## 4. ODF Local Volume Raw Disks (9 × 300GiB EBS gp3)

Disk raw Block untuk Local Storage Operator + ODF — LocalVolumeSet
(`hub/storage/local-volume/lvs.yaml`, storageClass `lvs-sc`, `volumeMode: Block`,
filter `minSize: 100G` non-rotational/rotational, nodeSelector label `node-role.kubernetes.io/odf`, toleration taint `node.ocs.openshift.io/storage`).

### 4.1 Konfigurasi

| Parameter              | Default  | Catatan                              |
| ---------------------- | -------- | ------------------------------------ |
| `odf_local_disk_count` | `9`      | 3 disk × 3 node `odf`                |
| `odf_local_disk_size`  | `300` GB | > `minSize: 100G` di lvs.yaml ✓      |
| `odf_local_disk_type`  | `gp3`    | 3000 IOPS / 125 MBps bawaan per disk |

Semua disk di AZ `ap-southeast-1a` (mengikuti `compute/machineSets/odf.yaml`) — EBS volume **wajib** satu AZ dengan instance tujuan. Cluster = single-AZ (subnet juga hanya 1a), jadi 1 AZ cukup; kalau nanti diperluas multi-AZ, tambahkan AZ ke `locals.odf_local_disk_azs` di `04-ebs-odf.tf`.

### 4.2 Apply & ambil list volume

```bash
terraform apply          # ikut toggle: hanya dibuat saat enable_hub = true
terraform output -json odf_local_volume_ids
# {
#  "ocp-lab-nonprod-odf-local-disk-01": "vol-0xxx",
#  ... (9 entri)
# }
```

### 4.3 Attach manual (AWS console/CLI — via bastion mascol atau workstation)

Raw disk **tidak di-attach otomatis** — node lifecycle odf dimiliki Machine API, bukan terraform (kalau tf bikin `aws_volume_attachment` ke i-instance ocp, state akan drift saat node re-created. karenanya attach manual).

```bash
# 1. instance ID 3 node odf
oc get nodes -l node-role.kubernetes.io/odf \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.providerID}{"\n"}{end}'
# contoh: aws://ap-southeast-1a/i-0abc...  → i-0abc...

# 2. attach 3 disk ke tiap node (urutan device /dev/sdf sdg sdh)
aws ec2 attach-volume --region ap-southeast-1 \
  --volume-id vol-0xxx --instance-id i-0xxx --device /dev/sdf
# ulangi sisa 8 disk: /dev/sdf..sdh tiap instance
```

> [!--volume-id vol-0xxx --instance-id i-0xxx --device /dev/sdf

# ulangi sisa 8 disk: /dev/sdf..sdh tiap instance

```

> [!TIP]
> Tidak perlu reboot. EBS di guest tampil sebagai `/dev/nvme2n1..n9` (penggantian nama device otonom saat linux attach; `lsblk` cek disk bersih tanpa partisi).

### 4.4 Lanjut ke LSO

Setelah 9 disk masing-masing terlihat raw (tanpa fs) di 3 node odf:
LocalVolumeSet `localvolumeset` auto-discover (`hub/storage/local-volume/` — lvd.yaml + lvs.yaml) → bikin PV Block + SC `lvs-sc` → ODF backup/dic afterward menyusul jalan.

---
```

> [!TIP]
> Tidak perlu reboot. EBS di guest tampil sebagai `/dev/nvme2n1..n9` (penggantian nama device otonom saat linux attach; `lsblk` cek disk bersih tanpa partisi).

### 4.4 Lanjut ke LSO

Setelah 9 disk masing-masing terlihat raw (tanpa fs) di 3 node odf:
LocalVolumeSet `localvolumeset` auto-discover (`hub/storage/local-volume/` — lvd.yaml + lvs.yaml) → bikin PV Block + SC `lvs-sc` → ODF backup/dic afterward menyusul jalan.

---
