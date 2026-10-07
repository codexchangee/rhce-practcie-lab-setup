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
# INSTALL APACHE
###########################################

echo "Installing Apache..."

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

curl -L "$URL" -o $WORKDIR/repo.tar.gz

echo "Extracting..."

tar -xzf $WORKDIR/repo.tar.gz -C $WORKDIR

EXTRACTED=$(find $WORKDIR -maxdepth 1 -type d -name "${GITHUB_REPO}-*")


###########################################
# WEB CONTENT SETUP
###########################################

echo "Setting up web content..."

sudo rm -rf /var/www/html/*
sudo mkdir -p /var/www/html/files


###########################################
# COPY HTML FILES
###########################################

echo "Copying HTML files..."

sudo find $EXTRACTED/test \
    -type f \
    -name "*.html" \
    -exec cp {} /var/www/html/ \;


###########################################
# COPY LAB FILES
#
# RHEL SYSTEM ROLES TAR IS EXCLUDED
###########################################

echo "Copying lab files..."

find "$EXTRACTED/files" -maxdepth 1 -type f \
    ! -name "redhat-rhel_system_roles-1.19.3.tar.gz" \
    -exec sudo cp {} /var/www/html/files/ \;


###########################################
# RHEL SYSTEM ROLES
###########################################

echo "Creating RHEL System Roles directory..."

sudo mkdir -p /var/www/html/index/rhel-system-roles

SYSTEM_ROLES="$EXTRACTED/files/redhat-rhel_system_roles-1.19.3.tar.gz"

if [ -f "$SYSTEM_ROLES" ]; then

    echo "Extracting RHEL System Roles..."

    sudo tar -xzf "$SYSTEM_ROLES" \
        -C /var/www/html/index/rhel-system-roles \
        --strip-components=1

    echo "RHEL System Roles extracted successfully."

else

    echo "ERROR: RHEL System Roles archive not found:"
    echo "$SYSTEM_ROLES"
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


# Create local Ansible directory

sudo mkdir -p /home/student/ansible
sudo chown -R student:student /home/student/ansible


# Initialize local Git repository

if [ ! -d /home/student/ansible/.git ]; then

    sudo -u student git \
        -C /home/student/ansible \
        init

fi


# Git identity

sudo -u student git \
    -C /home/student/ansible \
    config user.name "student"

sudo -u student git \
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
# CREATE SSH KEY FOR STUDENT
###########################################

if [ ! -f /home/student/.ssh/id_ed25519 ]; then

    sudo -u student mkdir -p /home/student/.ssh

    sudo -u student ssh-keygen \
        -t ed25519 \
        -N "" \
        -f /home/student/.ssh/id_ed25519

fi


###########################################
# AUTHORIZE STUDENT KEY ON UTILITY
###########################################

echo "Configuring Git SSH access..."

PUBKEY=$(cat /home/student/.ssh/id_ed25519.pub)

sshpass -p "$ROOT_PASSWORD" ssh \
    -o StrictHostKeyChecking=no \
    root@172.25.250.220 \
    "mkdir -p /root/.ssh && chmod 700 /root/.ssh && echo '$PUBKEY' >> /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys"


###########################################
# CONFIGURE GIT REMOTE
###########################################

sudo -u student git \
    -C /home/student/ansible \
    remote remove origin 2>/dev/null || true

sudo -u student git \
    -C /home/student/ansible \
    remote add origin \
    root@172.25.250.220:/var/lib/git/ansible.git

# RHEL location of Git server programs
sudo -u student git \
    -C /home/student/ansible \
    config remote.origin.receivepack \
    /usr/libexec/git-core/git-receive-pack

sudo -u student git \
    -C /home/student/ansible \
    config remote.origin.uploadpack \
    /usr/libexec/git-core/git-upload-pack


###########################################
# GIT TEST FILE
###########################################

sudo -u student bash -c \
    'echo "# RHEL RHCE Practice Lab" > /home/student/ansible/README.md'


###########################################
# COMMIT
###########################################

sudo -u student git \
    -C /home/student/ansible \
    add README.md

sudo -u student git \
    -C /home/student/ansible \
    commit -m "Initial lab repository"


###########################################
# PUSH
###########################################

sudo -u student git \
    -C /home/student/ansible \
    branch -M main

sudo -u student git \
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
echo "http://localhost/index/rhel-system-roles/"
echo ""
echo "Git:"
echo "/home/student/ansible"
echo ""
echo "======================================="
