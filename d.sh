#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "This script must be run with sudo."
    echo "Run: sudo bash b.sh"
    exit 1
fi

###########################################
# HOST ENTRIES
###########################################

HOST_ENTRIES=(
"172.25.250.10    servera.lab.example.com    node1"
"172.25.250.11    serverb.lab.example.com    node2"
"172.25.250.220   utility.lab.example.com    node3"
"172.25.250.12    serverc.lab.example.com    node4"
"172.25.250.13    serverd.lab.example.com    node5"
)

echo "Backing up /etc/hosts..."
cp /etc/hosts /etc/hosts.bak

for entry in "${HOST_ENTRIES[@]}"; do
    if ! grep -q "$entry" /etc/hosts; then
        echo "Adding entry: $entry"
        echo "$entry" | tee -a /etc/hosts > /dev/null
    else
        echo "Entry already exists: $entry"
    fi
done


###########################################
# INSTALL REQUIRED PACKAGES
###########################################

echo "Installing required packages..."

dnf install -y sshpass httpd git


###########################################
# INSTALL ANSIBLE COLLECTION
###########################################

echo "Installing ansible.posix..."

ansible-galaxy collection install ansible.posix


###########################################
# SSH + USER SETUP
###########################################

IP_ADDRESSES=(
"172.25.250.10"
"172.25.250.11"
"172.25.250.12"
"172.25.250.13"
"172.25.250.220"
)

ROOT_PASSWORD="redhat"

for ip in "${IP_ADDRESSES[@]}"; do

    echo "Connecting to $ip"

    sshpass -p "$ROOT_PASSWORD" ssh \
        -o StrictHostKeyChecking=no \
        root@$ip <<EOF

useradd -m admin 2>/dev/null
echo "admin:root" | chpasswd
echo "admin ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/admin

EOF

done

echo "######## PRACTICE LAB CREATED ########"


###########################################
# INSTALL APACHE
###########################################

echo "Installing Apache..."

systemctl enable --now httpd
