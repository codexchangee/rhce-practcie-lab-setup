#!/bin/bash

set -e

###########################################
# RHEL 10 RHCE PRACTICE LAB SETUP
###########################################

echo
echo "==============================================="
echo " RHEL 10 RHCE PRACTICE LAB SETUP"
echo "==============================================="
echo

###########################################
# CHECK USER
###########################################

CURRENT_USER=$(whoami)

if [ "$CURRENT_USER" != "student" ]; then
    echo
    echo "ERROR: This script must be run as student."
    echo
    echo "Run:"
    echo "  su - student"
    echo
    exit 1
fi

echo "Running as: $CURRENT_USER"


###########################################
# VARIABLES
###########################################

ROOT_PASSWORD="redhat"
ADMIN_PASSWORD="root"

GITHUB_USER="codexchangee"
GITHUB_REPO="rhce-practcie-lab-setup"
GITHUB_BRANCH="main"

ANSIBLE_DIR="/home/student/ansible"

UTILITY_IP="172.25.250.220"
UTILITY_HOST="utility.lab.example.com"

GIT_REPO="ansible.git"

###########################################
# HOST ENTRIES
###########################################

HOST_ENTRIES=(
"172.25.250.10    servera.lab.example.com    node1"
"172.25.250.11    serverb.lab.example.com    node2"
"172.25.250.220   utility.lab.example.com     node3"
"172.25.250.12    serverc.lab.example.com    node4"
"172.25.250.13    serverd.lab.example.com    node5"
)

echo
echo "Backing up /etc/hosts..."

sudo cp /etc/hosts /etc/hosts.bak.$(date +%Y%m%d%H%M%S)


for entry in "${HOST_ENTRIES[@]}"; do

    IP=$(echo "$entry" | awk '{print $1}')
    FQDN=$(echo "$entry" | awk '{print $2}')
    SHORT=$(echo "$entry" | awk '{print $3}')

    if ! grep -q "$FQDN" /etc/hosts; then

        echo "Adding entry: $entry"

        echo "$entry" |
            sudo tee -a /etc/hosts >/dev/null

    else

        echo "Entry already exists: $FQDN"

    fi

done


###########################################
# ADD MATERIAL SERVER NAMES
###########################################

echo
echo "Adding RHEL 10 material server names..."

if ! grep -q "server.network.example.com" /etc/hosts; then

    echo "172.25.250.220 server.network.example.com" |
        sudo tee -a /etc/hosts >/dev/null

fi


if ! grep -q "rhls.domain5.example.com" /etc/hosts; then

    echo "172.25.250.220 rhls.domain5.example.com" |
        sudo tee -a /etc/hosts >/dev/null

fi


###########################################
# INSTALL WORKSTATION PACKAGES
###########################################

echo
echo "Installing required workstation packages..."

sudo dnf install -y \
    ansible-core \
    sshpass \
    git \
    curl \
    wget \
    tar \
    gzip \
    httpd \
    policycoreutils-python-utils \
    openssh-clients \
    python3


###########################################
# INSTALL ANSIBLE COLLECTION
###########################################

echo
echo "Installing ansible.posix..."

ansible-galaxy collection install ansible.posix --force


###########################################
# CREATE ANSIBLE DIRECTORY
###########################################

echo
echo "Creating Ansible directory..."

mkdir -p "$ANSIBLE_DIR"

mkdir -p "$ANSIBLE_DIR/roles"

mkdir -p "$ANSIBLE_DIR/collections"

mkdir -p "$ANSIBLE_DIR/mycollection"

mkdir -p "$ANSIBLE_DIR/files"

mkdir -p "$ANSIBLE_DIR/templates"


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

echo
echo "==============================================="
echo " Creating admin and student users"
echo "==============================================="


for ip in "${IP_ADDRESSES[@]}"; do

    echo
    echo "Connecting to $ip..."

    sshpass -p "$ROOT_PASSWORD" \
    ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    root@$ip <<EOF

# -----------------------------------------------
# ADMIN USER
# -----------------------------------------------

useradd -m admin 2>/dev/null || true

echo "admin:$ADMIN_PASSWORD" | chpasswd

cat > /etc/sudoers.d/admin <<SUDO
admin ALL=(ALL) NOPASSWD:ALL
SUDO

chmod 440 /etc/sudoers.d/admin


# -----------------------------------------------
# STUDENT USER
# -----------------------------------------------
#
# Ansible connection is ADMIN.
# Student is also required for the cron question.
#

useradd -m student 2>/dev/null || true

echo "student:student" | chpasswd

# -----------------------------------------------
# Make sure Python exists
# -----------------------------------------------

dnf install -y python3 >/dev/null 2>&1 || true

EOF

done


echo
echo "######## PRACTICE LAB USERS CREATED ########"


###########################################
# CREATE ANSIBLE INVENTORY
###########################################

echo
echo "Creating Ansible inventory..."

cat > "$ANSIBLE_DIR/inventory" <<'EOF'

[dev]
system1

[test]
system2

[prod]
system3
system4

[webservers:children]
prod

[balancers]
system5

[all:vars]
ansible_user=admin
ansible_become=true
ansible_become_method=sudo
EOF


###########################################
# CREATE ANSIBLE CONFIG
###########################################

echo
echo "Creating ansible.cfg..."

cat > "$ANSIBLE_DIR/ansible.cfg" <<'EOF'

[defaults]

inventory = /home/student/ansible/inventory

remote_user = admin

roles_path = /home/student/ansible/roles:/home/student/ansible/mycollection/roles

collections_path = /home/student/ansible/collections:/home/student/ansible/mycollection/collections

host_key_checking = False

retry_files_enabled = False

interpreter_python = auto_silent


[privilege_escalation]

become = True

become_method = sudo

become_ask_pass = False

EOF


###########################################
# CREATE README
###########################################

cat > "$ANSIBLE_DIR/README.md" <<'EOF'

# RHEL 10 RHCE Practice Lab

Control node:

student

Ansible directory:

/home/student/ansible

Managed node connection user:

admin

Topology:

system1 = servera = dev

system2 = serverb = test

system3 = serverc = prod/webserver

system4 = serverd = prod/webserver

system5 = utility/balancer/Git/material server

Repositories:

EX294_BASE
EX294_STREM
CODE_READY_BUILDER

EOF


###########################################
# TEST ADMIN SSH
###########################################

echo
echo "==============================================="
echo " Testing admin SSH"
echo "==============================================="


for ip in "${IP_ADDRESSES[@]}"; do

    echo
    echo "Testing admin@$ip..."

    sshpass -p "$ADMIN_PASSWORD" \
    ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    admin@$ip \
    "hostname"

done


###########################################
# INSTALL APACHE ON WORKSTATION
###########################################

echo
echo "Installing Apache on workstation..."

sudo dnf install -y httpd

sudo systemctl enable --now httpd


###########################################
# DOWNLOAD RHEL PRACTICE REPOSITORY
###########################################

URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}/archive/refs/heads/${GITHUB_BRANCH}.tar.gz"

WORKDIR=$(mktemp -d)

echo
echo "Downloading RHEL practice repository..."

curl -L "$URL" -o "$WORKDIR/repo.tar.gz"


echo
echo "Extracting repository..."

tar -xzf "$WORKDIR/repo.tar.gz" -C "$WORKDIR"


EXTRACTED=$(find "$WORKDIR" \
    -maxdepth 1 \
    -type d \
    -name "${GITHUB_REPO}-*" |
    head -1)


if [ -z "$EXTRACTED" ]; then

    echo
    echo "ERROR: Repository extraction failed."
    exit 1

fi


echo
echo "Repository:"
echo "$EXTRACTED"


###########################################
# WEB CONTENT SETUP
###########################################

echo
echo "Setting up web content..."


sudo rm -rf /var/www/html/*

sudo mkdir -p /var/www/html/files


###########################################
# COPY HTML FILES
###########################################

if [ -d "$EXTRACTED/test" ]; then

    echo
    echo "Copying HTML files..."

    sudo find "$EXTRACTED/test" \
        -type f \
        -name "*.html" \
        -exec cp {} /var/www/html/ \;

else

    echo
    echo "WARNING: test directory not found."

fi


###########################################
# COPY LAB FILES
###########################################

if [ -d "$EXTRACTED/files" ]; then

    echo
    echo "Copying lab files..."

    sudo cp -r "$EXTRACTED/files/." \
        /var/www/html/files/

else

    echo
    echo "WARNING: files directory not found."

fi


###########################################
# PERMISSIONS
###########################################

echo
echo "Setting Apache permissions..."

sudo chown -R apache:apache /var/www/html

sudo chmod -R 755 /var/www/html


###########################################
# SELINUX
###########################################

echo
echo "Configuring SELinux..."

sudo dnf install -y policycoreutils-python-utils


sudo semanage fcontext \
    -a \
    -t httpd_sys_content_t \
    "/var/www/html(/.*)?" \
    2>/dev/null || true


sudo restorecon -Rv /var/www/html


###########################################
# RESTART APACHE
###########################################

sudo systemctl restart httpd


###########################################
# UTILITY SERVER SETUP
###########################################

echo
echo "==============================================="
echo " Configuring utility server"
echo "==============================================="


sshpass -p "$ROOT_PASSWORD" \
ssh \
-o StrictHostKeyChecking=no \
-o UserKnownHostsFile=/dev/null \
root@172.25.250.220 <<'EOF'


############################################
# INSTALL PACKAGES
############################################

dnf install -y \
    httpd \
    git \
    openssh-server \
    policycoreutils-python-utils


############################################
# ENABLE SERVICES
############################################

systemctl enable --now httpd

systemctl enable --now sshd


############################################
# FIREWALL
############################################

systemctl enable --now firewalld || true

firewall-cmd --permanent --add-service=http || true

firewall-cmd --permanent --add-service=ssh || true

firewall-cmd --reload || true


############################################
# GIT USER
############################################

useradd \
    -r \
    -m \
    -d /var/lib/git \
    -s /usr/bin/git-shell \
    git 2>/dev/null || true


############################################
# GIT REPOSITORY
############################################

mkdir -p /var/lib/git/ansible.git

if [ ! -f /var/lib/git/ansible.git/HEAD ]; then

    git init --bare /var/lib/git/ansible.git

fi

chown -R git:git /var/lib/git


############################################
# MATERIAL DIRECTORIES
############################################

mkdir -p \
    /var/www/html/materials \
    /var/www/html/index \
    /var/www/html/index/rhel-system-roles \
    /var/www/html/BaseOs \
    /var/www/html/AppStream \
    /var/www/html/CodeReadyLinuxBuilder \
    /var/www/html/materrials


chmod -R 755 /var/www/html


############################################
# SELINUX
############################################

restorecon -RFv /var/www/html >/dev/null 2>&1 || true


EOF


###########################################
# GIT SSH KEY
###########################################

echo
echo "==============================================="
echo " Configuring student Git authentication"
echo "==============================================="


mkdir -p /home/student/.ssh

chmod 700 /home/student/.ssh


if [ ! -f /home/student/.ssh/id_ed25519 ]; then

    ssh-keygen \
        -q \
        -t ed25519 \
        -N "" \
        -f /home/student/.ssh/id_ed25519 \
        -C "student@rhel10-rhce"

fi


PUBLIC_KEY=$(cat /home/student/.ssh/id_ed25519.pub)


###########################################
# INSTALL GIT SSH KEY
###########################################

sshpass -p "$ROOT_PASSWORD" \
ssh \
-o StrictHostKeyChecking=no \
-o UserKnownHostsFile=/dev/null \
root@172.25.250.220 <<EOF


mkdir -p /var/lib/git/.ssh

echo "$PUBLIC_KEY" \
    > /var/lib/git/.ssh/authorized_keys

chmod 700 /var/lib/git/.ssh

chmod 600 /var/lib/git/.ssh/authorized_keys

chown -R git:git /var/lib/git/.ssh

EOF


###########################################
# STUDENT SSH CONFIG
###########################################

cat > /home/student/.ssh/config <<EOF

Host utility-git

    HostName 172.25.250.220

    User git

    IdentityFile /home/student/.ssh/id_ed25519

    IdentitiesOnly yes

    StrictHostKeyChecking no

EOF


chmod 600 /home/student/.ssh/config


###########################################
# TEST GIT SSH
###########################################

echo
echo "Testing Git SSH..."

ssh \
    -o StrictHostKeyChecking=no \
    git@172.25.250.220 \
    "echo GIT_SSH_OK"


###########################################
# INITIALIZE STUDENT GIT REPOSITORY
###########################################

echo
echo "==============================================="
echo " Configuring candidate Git repository"
echo "==============================================="


cd "$ANSIBLE_DIR"


if [ ! -d ".git" ]; then

    git init

fi


git config user.name "student"

git config user.email "student@lab.example.com"

git branch -M main


GIT_REMOTE="ssh://git@172.25.250.220/var/lib/git/ansible.git"


if git remote get-url origin >/dev/null 2>&1; then

    git remote set-url origin "$GIT_REMOTE"

else

    git remote add origin "$GIT_REMOTE"

fi


###########################################
# INITIAL GIT COMMIT
###########################################

echo
echo "Creating initial Git commit..."

git add \
    inventory \
    ansible.cfg \
    README.md


git commit \
    -m "Initial RHEL 10 RHCE lab setup" \
    2>/dev/null || true


###########################################
# INITIAL GIT PUSH
###########################################

echo
echo "Uploading initial repository..."

git push -u origin main


###########################################
# CODE READY BUILDER DIRECTORY
###########################################

echo
echo "Creating CodeReady Linux Builder directory..."

sshpass -p "$ROOT_PASSWORD" \
ssh \
-o StrictHostKeyChecking=no \
-o UserKnownHostsFile=/dev/null \
root@172.25.250.220 <<'EOF'

mkdir -p /var/www/html/CodeReadyLinuxBuilder

chmod -R 755 /var/www/html/CodeReadyLinuxBuilder

restorecon -RFv /var/www/html/CodeReadyLinuxBuilder \
    >/dev/null 2>&1 || true

EOF


###########################################
# RHEL SYSTEM ROLES
###########################################

echo
echo "==============================================="
echo " Configuring RHEL System Roles"
echo "==============================================="


SYSTEM_ROLES_TAR="/home/student/redhat-rhel_system_roles-1.19.3.tar.gz"


if [ -f "$SYSTEM_ROLES_TAR" ]; then

    echo
    echo "System Roles archive found:"
    echo "$SYSTEM_ROLES_TAR"


    scp \
        -q \
        -o StrictHostKeyChecking=no \
        "$SYSTEM_ROLES_TAR" \
        root@172.25.250.220:/tmp/rhel-system-roles.tar.gz


    sshpass -p "$ROOT_PASSWORD" \
    ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    root@172.25.250.220 <<'EOF'


rm -rf /var/www/html/index/rhel-system-roles/*


tar -xzf \
    /tmp/rhel-system-roles.tar.gz \
    -C /var/www/html/index/rhel-system-roles \
    --strip-components=1


rm -f /tmp/rhel-system-roles.tar.gz


chmod -R 755 \
    /var/www/html/index/rhel-system-roles


restorecon -RFv \
    /var/www/html/index/rhel-system-roles \
    >/dev/null 2>&1 || true


EOF

else

    echo
    echo "WARNING:"
    echo "RHEL System Roles archive not found:"
    echo "$SYSTEM_ROLES_TAR"
    echo
    echo "Copy the archive to:"
    echo "$SYSTEM_ROLES_TAR"

fi


###########################################
# ANSIBLE PING TEST
###########################################

echo
echo "==============================================="
echo " Testing Ansible"
echo "==============================================="


cd "$ANSIBLE_DIR"


ansible --version


echo
echo "Running Ansible ping..."

ansible all -m ping


###########################################
# GIT TEST COMMIT
###########################################

echo
echo "==============================================="
echo " Testing Git upload"
echo "==============================================="


echo "RHEL 10 Git upload test" \
    > "$ANSIBLE_DIR/git-test.txt"


git add git-test.txt


git commit \
    -m "RHEL 10 Git upload test"


git push


###########################################
# GIT REMOTE CHECK
###########################################

echo
echo "Git remote:"

git remote -v


echo
echo "Remote branches:"

git ls-remote --heads origin


###########################################
# OPEN BROWSER
###########################################

echo
echo "Opening browser..."

xdg-open http://localhost 2>/dev/null || true

xdg-open http://localhost/files 2>/dev/null || true


###########################################
# FINAL INFORMATION
###########################################

echo
echo "==============================================="
echo " RHEL 10 PRACTICE LAB CREATED"
echo "==============================================="
echo

echo "Workstation user:"
echo "  student"

echo

echo "Ansible directory:"
echo "  /home/student/ansible"

echo

echo "Ansible inventory:"
echo "  /home/student/ansible/inventory"

echo

echo "Ansible config:"
echo "  /home/student/ansible/ansible.cfg"

echo

echo "Managed node user:"
echo "  admin"

echo

echo "Git server:"
echo "  172.25.250.220"

echo

echo "Git repository:"
echo "  ssh://git@172.25.250.220/var/lib/git/ansible.git"

echo

echo "Repository 1:"
echo "  EX294_BASE"
echo "  http://server.network.example.com/BaseOs"

echo

echo "Repository 2:"
echo "  EX294_STREM"
echo "  http://server.network.example.com/AppStream"

echo

echo "Repository 3:"
echo "  CODE_READY_BUILDER"
echo "  http://server.network.example.com/CodeReadyLinuxBuilder"

echo

echo "RHEL System Roles:"
echo "  http://server.network.example.com/index/rhel-system-roles/"

echo

echo "Practice files:"
echo "  http://localhost/files"

echo

echo "==============================================="
echo " Git test:"
echo "==============================================="
echo
echo "cd /home/student/ansible"
echo "echo hello > test.txt"
echo "git add test.txt"
echo "git commit -m 'Q1 test'"
echo "git push"
echo
echo "==============================================="

echo
echo "Script Executed Successfully"
echo
