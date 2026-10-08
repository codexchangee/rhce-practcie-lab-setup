#!/bin/bash

###########################################
# ROOT CHECK
###########################################

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run with sudo."
    echo "Run:"
    echo "curl -L https://raw.githubusercontent.com/codexchangee/rhce-practcie-lab-setup/main/e.sh | sudo bash"
    exit 1
fi

set -e

###########################################
# VARIABLES
###########################################

ROOT_PASSWORD="redhat"

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

echo "======================================="
echo "RHCE PRACTICE LAB SETUP"
echo "======================================="


###########################################
# INSTALL REQUIRED WORKSTATION PACKAGES
###########################################

echo "Installing required packages..."

dnf install -y \
    sshpass \
    httpd \
    git \
    curl \
    tar \
    policycoreutils-python-utils


###########################################
# CONFIGURE /etc/hosts
###########################################

echo "Configuring /etc/hosts..."

cp /etc/hosts /etc/hosts.bak

for entry in "${HOST_ENTRIES[@]}"; do

    if ! grep -Fqx "$entry" /etc/hosts; then
        echo "$entry" >> /etc/hosts
    fi

done


###########################################
# INSTALL ANSIBLE COLLECTION
###########################################

echo "Installing ansible.posix..."

ansible-galaxy collection install ansible.posix


###########################################
# CREATE ADMIN USER ON ALL NODES
###########################################

IP_ADDRESSES=(
"172.25.250.10"
"172.25.250.11"
"172.25.250.12"
"172.25.250.13"
"172.25.250.220"
)

echo "Creating admin user on all nodes..."

for ip in "${IP_ADDRESSES[@]}"; do

    echo "---------------------------------------"
    echo "Configuring $ip"
    echo "---------------------------------------"

    sshpass -p "$ROOT_PASSWORD" ssh \
        -o StrictHostKeyChecking=no \
        root@"$ip" <<'EOF'

if ! id admin >/dev/null 2>&1; then
    useradd -m admin
fi

echo "admin:root" | chpasswd

cat > /etc/sudoers.d/admin <<'SUDOEOF'
admin ALL=(ALL) NOPASSWD:ALL
SUDOEOF

chmod 440 /etc/sudoers.d/admin

EOF

done

echo "######## PRACTICE LAB CREATED ########"


###########################################
# INSTALL / START APACHE
###########################################

echo "Installing/starting Apache..."

systemctl enable --now httpd


###########################################
# DOWNLOAD GITHUB REPOSITORY
###########################################

GITHUB_USER="codexchangee"
GITHUB_REPO="rhce-practcie-lab-setup"
GITHUB_BRANCH="main"

URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}/archive/refs/heads/${GITHUB_BRANCH}.tar.gz"

WORKDIR=$(mktemp -d)

echo "Downloading repository..."

curl -fL "$URL" -o "$WORKDIR/repo.tar.gz"

echo "Extracting repository..."

tar -xzf "$WORKDIR/repo.tar.gz" -C "$WORKDIR"

EXTRACTED=$(find "$WORKDIR" \
    -maxdepth 1 \
    -mindepth 1 \
    -type d \
    -name "${GITHUB_REPO}-*" \
    | head -n1)

if [ -z "$EXTRACTED" ]; then
    echo "ERROR: GitHub repository extraction failed."
    exit 1
fi

echo "Repository extracted to:"
echo "$EXTRACTED"


###########################################
# VERIFY REQUIRED DIRECTORIES
###########################################

if [ ! -d "$EXTRACTED/test" ]; then
    echo "ERROR: test directory not found."
    exit 1
fi

if [ ! -d "$EXTRACTED/files" ]; then
    echo "ERROR: files directory not found."
    exit 1
fi


###########################################
# WEB CONTENT SETUP
###########################################

echo "Setting up web content..."

rm -rf /var/www/html/*

mkdir -p /var/www/html/files
mkdir -p /var/www/html/index/rhel-system-roles


###########################################
# COPY HTML FILES
###########################################

echo "Copying HTML files..."

find "$EXTRACTED/test" \
    -type f \
    -name "*.html" \
    -exec cp {} /var/www/html/ \;


###########################################
# COPY LAB FILES
###########################################

echo "Copying lab files..."

find "$EXTRACTED/files" \
    -maxdepth 1 \
    -type f \
    -exec cp {} /var/www/html/files/ \;


###########################################
# COPY RHEL SYSTEM ROLES DIRECTORY
###########################################

echo "Copying RHEL System Roles directory..."

if [ ! -d "$EXTRACTED/files/rhel-system-roles" ]; then

    echo "ERROR:"
    echo "$EXTRACTED/files/rhel-system-roles"
    echo "does not exist."

    exit 1

fi

cp -a \
    "$EXTRACTED/files/rhel-system-roles" \
    /var/www/html/files/

cp -a \
    "$EXTRACTED/files/rhel-system-roles/." \
    /var/www/html/index/rhel-system-roles/

echo "RHEL System Roles copied successfully."


###########################################
# APACHE PERMISSIONS
###########################################

chown -R apache:apache /var/www/html

chmod -R 755 /var/www/html


###########################################
# SELINUX
###########################################

echo "Configuring SELinux..."

semanage fcontext -a \
    -t httpd_sys_content_t \
    "/var/www/html(/.*)?" \
    2>/dev/null || true

semanage fcontext -a \
    -t httpd_sys_content_t \
    "/var/www/html/files(/.*)?" \
    2>/dev/null || true

restorecon -Rv /var/www/html


###########################################
# LOCAL GIT SETUP
###########################################

echo "======================================="
echo "SETTING UP LOCAL GIT"
echo "======================================="


###########################################
# CREATE ANSIBLE DIRECTORY
###########################################

echo "Creating /home/student/ansible..."

mkdir -p /home/student/ansible

chown -R student:student /home/student/ansible


###########################################
# CREATE LOCAL BARE GIT REPOSITORY
###########################################

echo "Creating local Git bare repository..."

mkdir -p /home/student/git

chown -R student:student /home/student/git

if [ ! -f /home/student/git/ansible.git/HEAD ]; then

    runuser -u student -- \
        git init --bare /home/student/git/ansible.git

fi


###########################################
# INITIALIZE WORKING GIT REPOSITORY
###########################################

if [ ! -d /home/student/ansible/.git ]; then

    echo "Initializing /home/student/ansible..."

    runuser -u student -- \
        git -C /home/student/ansible init

fi


###########################################
# GIT IDENTITY
###########################################

runuser -u student -- \
    git -C /home/student/ansible \
    config user.name "student"

runuser -u student -- \
    git -C /home/student/ansible \
    config user.email "student@lab.example.com"


###########################################
# CONFIGURE LOCAL GIT REMOTE
###########################################

echo "Configuring local Git remote..."

runuser -u student -- \
    git -C /home/student/ansible \
    remote remove origin 2>/dev/null || true

runuser -u student -- \
    git -C /home/student/ansible \
    remote add origin \
    /home/student/git/ansible.git


###########################################
# CREATE TEST FILE
###########################################

echo "Creating Git test file..."

runuser -u student -- \
    bash -c \
    'echo "# RHEL RHCE Practice Lab" > /home/student/ansible/README.md'


###########################################
# ADD TEST FILE
###########################################

runuser -u student -- \
    git -C /home/student/ansible \
    add README.md


###########################################
# INITIAL COMMIT
###########################################

runuser -u student -- \
    git -C /home/student/ansible \
    commit \
    -m "Initial lab repository"


###########################################
# SET MAIN BRANCH
###########################################

runuser -u student -- \
    git -C /home/student/ansible \
    branch -M main


###########################################
# PUSH TO LOCAL BARE REPOSITORY
###########################################

echo "Testing Git push..."

runuser -u student -- \
    git -C /home/student/ansible \
    push -u origin main


###########################################
# VERIFY GIT
###########################################

echo "Verifying Git..."

runuser -u student -- \
    git -C /home/student/ansible \
    status

echo ""

runuser -u student -- \
    git -C /home/student/ansible \
    remote -v

echo ""

echo "Git setup completed successfully."


###########################################
# RESTART APACHE
###########################################

systemctl restart httpd


###########################################
# FIX NODE1
###########################################

echo "Fixing node1..."

sshpass -p "$ROOT_PASSWORD" ssh \
    -o StrictHostKeyChecking=no \
    root@172.25.250.10 <<'EOF'

dnf remove -y python3-pyOpenSSL

EOF


###########################################
# FIX NODE3
###########################################

echo "Fixing node3..."

sshpass -p "$ROOT_PASSWORD" ssh \
    -o StrictHostKeyChecking=no \
    root@172.25.250.220 <<'EOF'

yum remove -y nginx

EOF


###########################################
# CLEANUP
###########################################

rm -rf "$WORKDIR"


###########################################
# OPEN BROWSER
###########################################

echo "Opening browser..."

xdg-open http://localhost 2>/dev/null || true

xdg-open http://localhost/files 2>/dev/null || true

xdg-open http://localhost/files/rhel-system-roles/ 2>/dev/null || true


###########################################
# DONE
###########################################

echo ""
echo "======================================="
echo "SCRIPT EXECUTED SUCCESSFULLY"
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
echo "Git working directory:"
echo "/home/student/ansible"
echo ""
echo "Git local repository:"
echo "/home/student/git/ansible.git"
echo ""
echo "======================================="
