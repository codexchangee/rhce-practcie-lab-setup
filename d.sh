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
# INSTALL APACHE + GIT
###########################################

echo "Installing Apache and Git..."

sudo dnf install -y httpd git

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

curl -L "$URL" -o "$WORKDIR/repo.tar.gz"

echo "Extracting..."

tar -xzf "$WORKDIR/repo.tar.gz" -C "$WORKDIR"

EXTRACTED=$(find "$WORKDIR" -maxdepth 1 -type d -name "${GITHUB_REPO}-*" | head -n1)


###########################################
# WEB CONTENT SETUP
###########################################

echo "Setting up web content..."

sudo rm -rf /var/www/html/*
sudo mkdir -p /var/www/html/files
sudo mkdir -p /var/www/html/index/rhel-system-roles


###########################################
# COPY HTML FILES
###########################################

echo "Copying HTML files..."

sudo find "$EXTRACTED/test" \
    -type f \
    -name "*.html" \
    -exec cp {} /var/www/html/ \;


###########################################
# COPY LAB FILES
###########################################

echo "Copying lab files..."

find "$EXTRACTED/files" -maxdepth 1 -type f \
    -exec sudo cp {} /var/www/html/files/ \;


###########################################
# COPY RHEL SYSTEM ROLES DIRECTORY
###########################################

echo "Copying RHEL System Roles directory..."

if [ -d "$EXTRACTED/files/rhel-system-roles" ]; then

    sudo cp -a \
        "$EXTRACTED/files/rhel-system-roles" \
        /var/www/html/files/

    sudo cp -a \
        "$EXTRACTED/files/rhel-system-roles/." \
        /var/www/html/index/rhel-system-roles/

    echo "RHEL System Roles directory copied successfully."

else

    echo "ERROR: rhel-system-roles directory not found:"
    echo "$EXTRACTED/files/rhel-system-roles"
    exit 1

fi


###########################################
# PERMISSIONS
###########################################

sudo chown -R apache:apache /var/www/html
sudo chmod -R 755 /var/www/html


###########################################
# SELINUX
###########################################

echo "Configuring SELinux..."

sudo dnf install -y policycoreutils-python-utils

sudo semanage fcontext -a \
    -t httpd_sys_content_t \
    "/var/www/html(/.*)?" 2>/dev/null || true

sudo semanage fcontext -a \
    -t httpd_sys_content_t \
    "/var/www/html/files(/.*)?" 2>/dev/null || true

sudo restorecon -Rv /var/www/html


###########################################
# GIT SETUP
###########################################

echo "======================================="
echo "Setting up Git..."
echo "======================================="


###########################################
# CREATE LOCAL ANSIBLE DIRECTORY
###########################################

runuser -u student -- mkdir -p /home/student/ansible

chown -R student:student /home/student/ansible


###########################################
# INITIALIZE LOCAL GIT REPOSITORY
###########################################

if [ ! -d /home/student/ansible/.git ]; then

    runuser -u student -- git \
        -C /home/student/ansible \
        init

fi


###########################################
# GIT IDENTITY
###########################################

runuser -u student -- git \
    -C /home/student/ansible \
    config user.name "student"

runuser -u student -- git \
    -C /home/student/ansible \
    config user.email "student@lab.example.com"


###########################################
# CREATE GIT SERVER ON UTILITY
###########################################

echo "Creating Git repository on utility..."

sshpass -p "$ROOT_PASSWORD" ssh \
    -o StrictHostKeyChecking=no \
    root@172.25.250.220 <<EOF

dnf install -y git

mkdir -p /var/lib/git/ansible.git

if [ ! -f /var/lib/git/ansible.git/HEAD ]; then
    git init --bare /var/lib/git/ansible.git
fi

EOF


###########################################
# CONFIGURE GIT REMOTE
###########################################

echo "Configuring Git remote..."

runuser -u student -- git \
    -C /home/student/ansible \
    remote remove origin 2>/dev/null || true

runuser -u student -- git \
    -C /home/student/ansible \
    remote add origin \
    root@172.25.250.220:/var/lib/git/ansible.git


###########################################
# REMOVE OLD GIT RECEIVE-PACK SETTINGS
###########################################

runuser -u student -- git \
    -C /home/student/ansible \
    config --unset remote.origin.receivepack 2>/dev/null || true

runuser -u student -- git \
    -C /home/student/ansible \
    config --unset remote.origin.uploadpack 2>/dev/null || true


###########################################
# GIT TEST FILE
###########################################

runuser -u student -- bash -c \
    'echo "# RHEL RHCE Practice Lab" > /home/student/ansible/README.md'


###########################################
# COMMIT
###########################################

runuser -u student -- git \
    -C /home/student/ansible \
    add README.md

runuser -u student -- git \
    -C /home/student/ansible \
    commit -m "Initial lab repository" || true


###########################################
# PUSH
###########################################

runuser -u student -- git \
    -C /home/student/ansible \
    branch -M main

runuser -u student -- git \
    -C /home/student/ansible \
    push -u origin main


echo "Git repository test completed successfully."


###########################################
# RESTART APACHE
###########################################

sudo systemctl restart httpd


###########################################
# FIX NODE1
###########################################

echo "Fixing node1..."

sshpass -p "$ROOT_PASSWORD" ssh \
    -o StrictHostKeyChecking=no \
    root@172.25.250.10 <<EOF

dnf remove -y python3-pyOpenSSL

EOF


###########################################
# FIX NODE3
###########################################

echo "Fixing node3..."

sshpass -p "$ROOT_PASSWORD" ssh \
    -o StrictHostKeyChecking=no \
    root@172.25.250.220 <<EOF

yum remove -y nginx

EOF


###########################################
# OPEN BROWSER
###########################################

echo "Opening browser..."

xdg-open http://localhost 2>/dev/null
xdg-open http://localhost/files 2>/dev/null
xdg-open http://localhost/files/rhel-system-roles/ 2>/dev/null


###########################################
# DONE
###########################################

echo "======================================="
echo "Script Executed Successfully"
echo "======================================="
echo ""
echo "Main UI:"
echo "http://localhost"
echo ""
echo "Lab Files:"
echo "http://localhost/files"
echo ""
echo "RHEL System Roles:"
echo "http://localhost/files/rhel-system-roles/"
echo ""
echo "Git:"
echo "/home/student/ansible"
echo ""
echo "======================================="
