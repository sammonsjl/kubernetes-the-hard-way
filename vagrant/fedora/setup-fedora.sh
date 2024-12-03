#!/bin/bash

# Resize root filesystem
growpart /dev/vda 4 &> /dev/null
btrfs filesystem resize max / &> /dev/null

# Enable password auth in sshd so we can use ssh-copy-id
sed -i --regexp-extended 's/#?PasswordAuthentication (yes|no)/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i --regexp-extended 's/#?Include \/etc\/ssh\/sshd_config.d\/\*.conf/#Include \/etc\/ssh\/sshd_config.d\/\*.conf/' /etc/ssh/sshd_config
sed -i --regexp-extended 's/#?UsePAM no/UsePAM yes/' /etc/ssh/sshd_config
sed -i 's/KbdInteractiveAuthentication no/KbdInteractiveAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

setenforce 0

systemctl restart sshd

if [ ! -d /home/vagrant/.ssh ]
then
    mkdir /home/vagrant/.ssh
    chmod 700 /home/vagrant/.ssh
    chown vagrant:vagrant /home/vagrant/.ssh
fi

echo "Running dnf update -y"

sh -c 'sudo dnf update -y' &> /dev/null
sh -c 'sudo dnf install -y bind-utils openssl sshpass tmux vim wget' &> /dev/null

sh -c 'sudo systemctl unmask systemd-binfmt.service'
sh -c 'sudo systemctl start systemd-binfmt.service'
