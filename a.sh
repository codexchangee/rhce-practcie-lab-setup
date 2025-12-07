#!/bin/bash

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
        echo "$entry" | sudo tee -a /etc/hosts > /dev/null
    else
        echo "Entry already exists: $entry"
    fi
done

echo "Installing ansible.posix..."
ansible-galaxy collection install ansible.posix

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
    sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no root@$ip <<EOF
        useradd -m admin
        echo "admin:root" | chpasswd
        echo "admin ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/admin
EOF
done

echo "######## PRACTICE LAB CREATED ########"

echo "Installing Apache..."
sudo dnf install -y httpd
sudo systemctl enable --now httpd

#########################################################
# DOWNLOAD FILES FROM GITHUB REPO
#########################################################

GITHUB_USER="codexchangee"
GITHUB_REPO="rhce-practcie-lab-setup"
GITHUB_BRANCH="main"

URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}/archive/refs/heads/${GITHUB_BRANCH}.tar.gz"

WORKDIR=$(mktemp -d)

echo "Downloading files from GitHub..."
curl -L "$URL" -o $WORKDIR/repo.tar.gz

echo "Extracting..."
tar -xzf $WORKDIR/repo.tar.gz -C $WORKDIR

EXTRACTED=$(find $WORKDIR -maxdepth 1 -type d -name "${GITHUB_REPO}-*")

echo "Copying files to /var/www/html/files..."
sudo mkdir -p /var/www/html/files
sudo cp -r $EXTRACTED/files/* /var/www/html/files/

sudo chown -R apache:apache /var/www/html/files
sudo chmod -R 755 /var/www/html/files

sudo systemctl restart httpd




###########################################
# FIX NODE1: REMOVE python3-pyOpenSSL
############################################

echo "Fixing node1: Removing python3-pyOpenSSL..."

sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no root@172.25.250.10 <<EOF
sudo dnf remove -y python3-pyOpenSSL
EOF

if [ $? -eq 0 ]; then
    echo "python3-pyOpenSSL removed successfully from node1"
else
    echo "Failed to remove python3-pyOpenSSL from node1"
fi


############################################
# FIX NODE3: REMOVE nginx
############################################

echo "Fixing node3: Removing nginx..."

sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no root@172.25.250.220 <<EOF
yum remove nginx -y
EOF

if [ $? -eq 0 ]; then
    echo "nginx removed successfully from node3"
else
    echo "Failed to remove nginx from node3"
fi





echo "Opening browser..."
xdg-open http://localhost/files 2>/dev/null

echo "Script Executed Successfully"
