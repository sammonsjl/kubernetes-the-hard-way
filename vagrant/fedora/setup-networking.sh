#!/bin/bash

nmcli con delete "Wired connection 1" &> /dev/null
nmcli con delete "Wired connection 2" &> /dev/null

nmcli con add ifname ens5 type ethernet con-name ens5 \
  connection.autoconnect yes ipv4.method auto &> /dev/null

echo "Setting machine ip to: " ${IPADDR}

nmcli con add ifname ens6 type ethernet con-name ens6 \
  connection.autoconnect yes ipv4.method manual \
  ipv4.address ${IPADDR}/24 \
  ipv4.gateway 192.168.100.1 ipv4.dns 8.8.8.8 &> /dev/null