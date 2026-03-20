#!/bin/bash

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
        echo "$entry" | sudo tee -a /etc/hosts > /dev/null
    else
        echo "Entry already exists: $entry"
    fi
done

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
    sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no root@$ip <<EOF
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
sudo dnf install -y httpd
sudo systemctl enable --now httpd

###########################################
# DOWNLOAD FROM GITHUB
###########################################
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

###########################################
# WEB CONTENT SETUP
###########################################
echo "Setting up web content..."

# Clean old content
sudo rm -rf /var/www/html/*
sudo mkdir -p /var/www/html/files

# Copy HTML files → /
echo "Copying HTML files..."
sudo find $EXTRACTED/test -type f -name "*.html" -exec cp {} /var/www/html/ \;

# Copy lab files → /files
echo "Copying lab files..."
sudo cp -r $EXTRACTED/files/* /var/www/html/files/

###########################################
# PERMISSIONS
###########################################
sudo chown -R apache:apache /var/www/html
sudo chmod -R 755 /var/www/html

###########################################
# SELINUX (PERSISTENT FIX)
###########################################
echo "Configuring SELinux..."

sudo dnf install -y policycoreutils-python-utils

# Main web content
sudo semanage fcontext -a -t httpd_sys_content_t "/var/www/html(/.*)?"

# Files directory (download content)
sudo semanage fcontext -a -t httpd_sys_content_t "/var/www/html/files(/.*)?"

# Apply context
sudo restorecon -Rv /var/www/html

###########################################
# RESTART APACHE
###########################################
sudo systemctl restart httpd

###########################################
# FIX NODE1
###########################################
echo "Fixing node1..."
sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no root@172.25.250.10 <<EOF
dnf remove -y python3-pyOpenSSL
EOF

###########################################
# FIX NODE3
###########################################
echo "Fixing node3..."
sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no root@172.25.250.220 <<EOF
yum remove -y nginx
EOF

###########################################
# OPEN BROWSER
###########################################
echo "Opening browser..."
xdg-open http://localhost 2>/dev/null
xdg-open http://localhost/files 2>/dev/null

###########################################
# DONE
###########################################
echo "======================================="
echo "Script Executed Successfully"
echo "Main UI:     http://localhost"
echo "Lab Files:   http://localhost/files"
echo "======================================="
