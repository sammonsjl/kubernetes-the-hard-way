#!/bin/bash

nmcli con delete "Wired connection 1"
nmcli con delete "Wired connection 2"
nmcli con delete "enp0s2"

nmcli con add ifname eth0 type ethernet con-name eth0 \
  connection.autoconnect yes ipv4.method auto

nmcli con add ifname eth1 type ethernet con-name eth1 \
  connection.autoconnect yes ipv4.method manual \
  ipv4.address "$(< /etc/sysconfig/network-scripts/ifcfg-eth1 grep IPADDR | cut -d "=" -f2)"/24 \
  ipv4.gateway 192.168.100.1 ipv4.dns 8.8.8.8