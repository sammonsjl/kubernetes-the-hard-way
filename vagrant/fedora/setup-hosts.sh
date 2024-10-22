#!/bin/bash
#
# Set up /etc/hosts so we can resolve all the machines in the KVM network
set -e
IFNAME=$1
THISHOST=$2

# Host will have 3 interfaces: lo, DHCP assigned NAT network and static on VM network
# We want the VM network
PRIMARY_IP="$(ip -4 addr show | grep "inet" | grep -E -v '(dynamic|127\.0\.0)' | awk '{print $2}' | cut -d/ -f1)"
NETWORK=$(echo $PRIMARY_IP | awk 'BEGIN {FS="."} ; { printf("%s.%s.%s", $1, $2, $3) }')
#sed -e "s/^.*${HOSTNAME}.*/${PRIMARY_IP} ${HOSTNAME} ${HOSTNAME}.local/" -i /etc/hosts

cat >> /etc/profile <<EOF
export PRIMARY_IP=${PRIMARY_IP}
export ARCH=amd64
EOF


# Create /etc/hosts about other hosts

cat > /etc/hosts <<EOF
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
${NETWORK}.11  controlplane01
${NETWORK}.12  controlplane02
${NETWORK}.13  controlplane03
${NETWORK}.21  node01
${NETWORK}.22  node02
${NETWORK}.30  loadbalancer
EOF
