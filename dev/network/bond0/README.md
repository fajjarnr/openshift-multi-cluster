ini contoh config bond0 dari temen

```sh
#!/bin/bash

# Konfigurasi ISO untuk worker nodes dengan bonding interface
for i in {16..39}; do
  worker=$((i - 14))
  ip_address="10.202.100.$i"

  # Update IP address di file konfigurasi bond0
  sed -i "s|^address1=.*|address1=${ip_address}/24,10.202.100.1|" bond0.nmconnection

  # Tampilkan informasi build
  echo "Building worker${worker} → IP ${ip_address}"
  echo -n "worker${worker} config → "
  grep '^address1=' bond0.nmconnection

  # Customize CoreOS ISO dengan konfigurasi network
  coreos-installer iso customize \
    --network-keyfile bond0.nmconnection \
    --network-keyfile ens1f0np0.nmconnection \
    --network-keyfile ens4f1np1.nmconnection \
    --dest-device /dev/sda \
    --dest-ignition ../worker.ign \
    --dest-karg-append "bond=bond0:ens1f0np0,ens4f1np1:mode=802.3ad,lacp_rate=fast,miimon=100,xmit_hash_policy=layer2+3" \
    --dest-karg-append "rd.neednet=1" \
    -o /root/worker-${worker}.iso \
    rhcos-4.18.27-x86_64-live.x86_64.iso

  echo "✓ worker${worker}.iso created successfully"
  echo "----------------------------------------"
done

echo "All worker ISOs created!"
```

ini benar ga ya coba cek bisa di sesuaikan nama ens192 dll agar saya paham
