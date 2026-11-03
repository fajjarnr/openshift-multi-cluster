# RHCOS Cross-Bonding Lab on VMware Fusion

Lab untuk menguji konfigurasi **cross-bonding 2 NIC × 2 port** pada Red
Hat Enterprise Linux CoreOS (RHCOS) menggunakan `coreos-installer`. Lab
ini berdiri sendiri dan **tidak memerlukan instalasi OpenShift**.

## 1. Tujuan

- Memodelkan server bare-metal dengan dua NIC, masing-masing memiliki
  dua port.
- Membuat dua bond dengan pola cross-connection:
  - `bond0`: NIC 0 Port 0 + NIC 1 Port 1, untuk jaringan
    OCP/primary.
  - `bond1`: NIC 0 Port 1 + NIC 1 Port 0, untuk VM traffic.
- Menyediakan fondasi untuk menguji failover, konfigurasi MTU, dan
  kemudian bridge/NAD sebagai eksperimen lanjutan.
- Memahami pemetaan VMware virtual adapter ke interface Linux di
  RHCOS.

## 2. Topologi target

```text
                          +----------------+
                          |  MGMT Switch   |
                          +--------+-------+
                                   |
                                [ MGMT ]
                                   |
       +---------------------------+---------------------------+
       |                                                       |
+------+-------+                                       +-------+------+
|   Switch A   |                                       |   Switch B  |
+------+-------+                                       +-------+------+
       |  \                                                   /  |
       |   \                                                 /   |
       |    \                                               /    |
       |     +-------------------+   +---------------------+     |
       |                         |   |                           |
       |                   +-----+---+-----+                     |
       +-------------------| NIC 0 | NIC 1 |---------------------+
                           |               |
                           | Port 0  Port 1|
                           +---------------+

Cross-bond mapping:
  bond0 = NIC 0 Port 0 (Switch A) + NIC 1 Port 1 (Switch B)
  bond1 = NIC 0 Port 1 (Switch B) + NIC 1 Port 0 (Switch A)
```

Diagram di atas adalah gambaran konseptual. Untuk koneksi
production-like, kedua switch harus menyediakan desain Layer 2 yang
sesuai untuk VLAN/subnet yang dibawa oleh masing-masing bond. Bonding ke
dua switch yang benar-benar independen tidak otomatis memberi redundansi
yang valid hanya dengan menghubungkan dua kabel; konfigurasi switch dan
mode bonding juga harus cocok.

## 3. VMware Fusion: empat virtual adapter

Mapping interface Linux sudah diamati di RHCOS dengan menonaktifkan
Adapter 1 dan 3: `enp2s0` dan `enp3s0` berubah menjadi `DOWN`, sementara
`enp11s0` dan `enp26s0` tetap `UP`.

---

VMware Fusion Interface Peran Jaringan logis Bond
adapter RHCOS bare-metal

---

Adapter 1 `enp2s0` NIC 0, Port 0 OCP / Switch A `bond0`

Adapter 2 `enp11s0` NIC 0, Port 1 VM / Switch B `bond1`

Adapter 3 `enp3s0` NIC 1, Port 0 VM / Switch A `bond1`

Adapter 4 `enp26s0` NIC 1, Port 1 OCP / Switch B `bond0`

---

Target bond:

```text
bond0 = enp2s0 + enp26s0
bond1 = enp11s0 + enp3s0
```

> Nama interface diverifikasi pada VM/lab ini. Jangan menganggap nama
> interface akan sama pada VM atau hardware lain. Verifikasi kembali
> menggunakan MAC address dan dengan disconnect satu adapter pada satu
> waktu.

## 4. Rencana alamat jaringan

---

Jaringan logis Subnet contoh MTU rencana Kegunaan

---

OCP / `bond0` `10.202.100.0/24` 1500 Primary network
dalam simulasi

VM / `bond1` `10.202.200.0/24` 9000 (tahap lanjutan) VM traffic dalam
simulasi

Management Disesuaikan dengan Sesuai jaringan Akses host/lab,
lab bila diperlukan

---

Alamat IP `10.202.100.0/24` dan `10.202.200.0/24` adalah subnet contoh
yang dipakai pada setup saat ini. Tentukan IP statis yang unik sebelum
konfigurasi final.

**Penting:** `bond0` umumnya menerima konfigurasi IP host untuk jaringan
primary. `bond1` untuk VM traffic dapat dibiarkan tanpa IP host bila
nantinya digunakan sebagai port untuk bridge. Jangan memberikan alamat
IP yang sama ke slave dan bond.

MTU 9000 pada `bond1` baru dianggap valid jika seluruh jalur mendukung
jumbo frames, termasuk virtual NIC, jaringan VMware, bridge, dan
endpoint VM. Mengatur MTU di interface RHCOS saja tidak membuktikan
jumbo frames berjalan end-to-end.

## 5. Batasan simulasi VMware Fusion

Empat virtual NIC dapat digunakan untuk menguji pembentukan bond dan
perilaku link failover. Namun, empat virtual NIC **tidak otomatis
merepresentasikan dua kartu NIC fisik atau dua switch fisik yang
independen**.

Untuk tahap awal, gunakan jaringan virtual yang sesuai dan verifikasi: -
Interface yang tepat menjadi slave setiap bond. - Bond tetap `UP` ketika
salah satu slave terputus. - Konektivitas tetap berjalan melalui jalur
yang tersisa. - Perilaku tersebut benar-benar sesuai dengan mode bonding
yang dipilih.

Jika OCP-A/OCP-B atau VM-A/VM-B dimaksudkan sebagai dua jalur switch
yang independen, dibutuhkan simulasi switch tambahan (misalnya VM Linux
bridge/Open vSwitch) dan desain Layer 2 yang sesuai. Jangan menganggap
dua network segment terpisah dapat saling menggantikan dalam satu bond
tanpa konfigurasi jaringan yang mendukungnya.

## 6. Urutan eksperimen

1. **Verifikasi adapter**\
   Cocokkan Adapter 1--4 dengan interface Linux menggunakan MAC
   address, PCI path, atau disconnect/reconnect adapter satu per satu.

2. **Siapkan konfigurasi RHCOS**\
   Siapkan NetworkManager keyfile untuk `bond0` dan `bond1`, lalu
   gunakan `coreos-installer iso customize` untuk memasukkannya ke ISO.
   Validasi sintaks dan dukungan parameter terhadap versi RHCOS yang
   digunakan.

3. **Uji `bond0`**\
   Mulai dengan mode `active-backup`, MTU 1500, dan IP host yang unik
   pada `bond0`.

4. **Uji `bond1`**\
   Bentuk bond dari `enp11s0` dan `enp3s0`. Untuk tahap awal, jangan
   tambahkan bridge atau NAD dahulu.

5. **Uji failover**\
   Putuskan satu adapter pada satu waktu dan periksa status bond serta
   konektivitas. Pastikan adapter kembali normal setelah diaktifkan
   lagi.

6. **Eksperimen lanjutan**\
   Setelah cross-bonding dan failover terverifikasi, uji MTU 9000 pada
   jalur VM. Bridge, NetworkAttachmentDefinition (NAD), dan OpenShift
   Virtualization berada di luar cakupan tahap awal ini.

## 7. Perintah pemeriksaan

```bash
ip -br link
ip -br address
nmcli device status
```

Untuk melihat detail bond setelah terbentuk:

```bash
cat /proc/net/bonding/bond0
cat /proc/net/bonding/bond1
```

Untuk melihat MAC address setiap interface:

```bash
for i in /sys/class/net/en*; do
  printf '%-10s %s\n' "$(basename "$i")" "$(cat "$i/address")"
done
```

## 8. Di luar cakupan

Tahap awal ini tidak mencakup: - Instalasi atau konfigurasi cluster
OpenShift. - Konfigurasi NMState Operator/NNCP. - Pembuatan bridge dan
NAD. - Validasi LACP lintas-switch/MLAG. - Klaim bahwa VMware Fusion
menyediakan redundansi switch fisik.

Semua perubahan jaringan sebaiknya dilakukan dari console VM, karena
perubahan pada interface primary dapat memutus akses jaringan.

referensi :

- <https://www.redhat.com/en/blog/red-hat-enterprise-linux-coreos-customization>
- <https://medium.com/swlh/guide-okd-4-5-single-node-cluster-832693cb752b>
