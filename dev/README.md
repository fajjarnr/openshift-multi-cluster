```sh
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519

mkdir ocp-installer
./openshift-install create manifests --dir ocp-installer
./openshift-install create ignition-configs --dir ocp-installer

python3 -m http.server 8080 --bind 0.0.0.0

sudo firewall-cmd --permanent --add-port=8080/tcp

sudo firewall-cmd --reload

curl <http://bastion:8080/>

bond=bond0:enp2s0,enp26s0:mode=active-backup,miimon=100
ip=10.202.100.131::10.202.100.2:255.255.255.0::bond0:none:10.202.100.220

cat /proc/net/bonding/bond0

ip link set enp26s0 down

cat /proc/net/bonding/bond0
ip link set enp26s0 up
```
