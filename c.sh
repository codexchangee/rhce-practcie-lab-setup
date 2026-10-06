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

curl -L "$URL" -o "$WORKDIR/repo.tar.gz"

echo "Extracting..."

tar -xzf "$WORKDIR/repo.tar.gz" -C "$WORKDIR"

EXTRACTED=$(find "$WORKDIR" -maxdepth 1 -type d -name "${GITHUB_REPO}-*")


###########################################
# WEB CONTENT SETUP
###########################################

echo "Setting up web content..."

# Clean old content
sudo rm -rf /var/www/html/*

sudo mkdir -p /var/www/html/files


# Copy HTML files → /
echo "Copying HTML files..."

sudo find "$EXTRACTED/test" \
    -type f \
    -name "*.html" \
    -exec cp {} /var/www/html/ \;


# Copy lab files → /files
echo "Copying lab files..."

sudo cp -r "$EXTRACTED/files/"* /var/www/html/files/


###########################################
# RHEL SYSTEM ROLES
###########################################

echo "Setting up RHEL System Roles..."

SYSTEM_ROLES_ARCHIVE="/home/student/redhat-rhel_system_roles-1.19.3.tar.gz"

if [ ! -f "$SYSTEM_ROLES_ARCHIVE" ]; then

    echo "ERROR: RHEL System Roles archive was not found:"
    echo "$SYSTEM_ROLES_ARCHIVE"
    echo ""
    echo "Please place the file at:"
    echo "/home/student/redhat-rhel_system_roles-1.19.3.tar.gz"
    echo ""

    exit 1

fi


UTILITY_IP="172.25.250.220"

echo "Copying RHEL System Roles archive to utility..."

sshpass -p "$ROOT_PASSWORD" scp \
    -o StrictHostKeyChecking=no \
    "$SYSTEM_ROLES_ARCHIVE" \
    root@$UTILITY_IP:/tmp/rhel-system-roles.tar.gz


echo "Extracting RHEL System Roles on utility..."

sshpass -p "$ROOT_PASSWORD" ssh \
    -o StrictHostKeyChecking=no \
    root@$UTILITY_IP <<'EOF'

set -e

ROLE_WEB_DIR="/var/www/html/index/rhel-system-roles"
ROLE_TMP_DIR="/tmp/rhel-system-roles-extract"

rm -rf "$ROLE_WEB_DIR"
rm -rf "$ROLE_TMP_DIR"

mkdir -p "$ROLE_WEB_DIR"
mkdir -p "$ROLE_TMP_DIR"

tar -xzf /tmp/rhel-system-roles.tar.gz \
    -C "$ROLE_TMP_DIR"


# Handle archive with a top-level directory
TOP_DIR=$(find "$ROLE_TMP_DIR" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d \
    | head -n 1)


if [ -n "$TOP_DIR" ] && [ -d "$TOP_DIR/roles" ]; then

    cp -a "$TOP_DIR"/. "$ROLE_WEB_DIR"/

else

    cp -a "$ROLE_TMP_DIR"/. "$ROLE_WEB_DIR"/

fi


# Remove temporary archive
rm -f /tmp/rhel-system-roles.tar.gz

# Remove temporary extraction directory
rm -rf "$ROLE_TMP_DIR"


# Web permissions
chown -R apache:apache "$ROLE_WEB_DIR"
chmod -R 755 "$ROLE_WEB_DIR"

echo "RHEL System Roles installed successfully."

EOF


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
sudo semanage fcontext -a \
    -t httpd_sys_content_t \
    "/var/www/html(/.*)?" 2>/dev/null || true


# Files directory
sudo semanage fcontext -a \
    -t httpd_sys_content_t \
    "/var/www/html/files(/.*)?" 2>/dev/null || true


# Apply context
sudo restorecon -Rv /var/www/html


###########################################
# GIT SERVER SETUP
###########################################

echo "======================================="
echo "Setting up Git server..."
echo "======================================="


echo "Installing Git on utility..."

sshpass -p "$ROOT_PASSWORD" ssh \
    -o StrictHostKeyChecking=no \
    root@$UTILITY_IP <<'EOF'

set -e

dnf install -y git openssh-server

systemctl enable --now sshd


# Create git user
id git >/dev/null 2>&1 || useradd -m -d /home/git -s /usr/bin/git-shell git


# Make sure git-shell exists
GIT_SHELL=$(command -v git-shell)

if ! grep -q "^${GIT_SHELL}$" /etc/shells; then
    echo "$GIT_SHELL" >> /etc/shells
fi

usermod -s "$GIT_SHELL" git


# Git repository directory
mkdir -p /var/lib/git

chown git:git /var/lib/git


# Create bare repository
if [ ! -d /var/lib/git/ansible.git ]; then

    sudo -u git git init --bare /var/lib/git/ansible.git

fi


# SSH directory for git user
mkdir -p /home/git/.ssh

chmod 700 /home/git/.ssh

touch /home/git/.ssh/authorized_keys

chmod 600 /home/git/.ssh/authorized_keys

chown -R git:git /home/git/.ssh

EOF


###########################################
# CREATE STUDENT SSH KEY FOR GIT
###########################################

echo "Creating SSH key for student..."

sudo -u student mkdir -p /home/student/.ssh

sudo chmod 700 /home/student/.ssh

sudo chown -R student:student /home/student/.ssh


if [ ! -f /home/student/.ssh/id_ed25519 ]; then

    sudo -u student ssh-keygen \
        -t ed25519 \
        -N "" \
        -f /home/student/.ssh/id_ed25519

fi


###########################################
# INSTALL STUDENT PUBLIC KEY ON GIT SERVER
###########################################

echo "Installing student SSH key on Git server..."

sshpass -p "$ROOT_PASSWORD" scp \
    -o StrictHostKeyChecking=no \
    /home/student/.ssh/id_ed25519.pub \
    root@$UTILITY_IP:/tmp/student_git_key.pub


sshpass -p "$ROOT_PASSWORD" ssh \
    -o StrictHostKeyChecking=no \
    root@$UTILITY_IP <<'EOF'

set -e

mkdir -p /home/git/.ssh

cat /tmp/student_git_key.pub >> /home/git/.ssh/authorized_keys

rm -f /tmp/student_git_key.pub

chmod 700 /home/git/.ssh
chmod 600 /home/git/.ssh/authorized_keys

chown -R git:git /home/git/.ssh

EOF


###########################################
# CREATE STUDENT ANSIBLE DIRECTORY
###########################################

echo "Creating /home/student/ansible..."

sudo mkdir -p /home/student/ansible

sudo chown -R student:student /home/student/ansible


###########################################
# INITIALIZE LOCAL GIT REPOSITORY
###########################################

echo "Initializing Git repository..."

if [ ! -d /home/student/ansible/.git ]; then

    sudo -u student bash -c \
        'cd /home/student/ansible && git init'

fi


###########################################
# CONFIGURE GIT USER
###########################################

sudo -u student git \
    -C /home/student/ansible \
    config user.name "student"


sudo -u student git \
    -C /home/student/ansible \
    config user.email "student@lab.example.com"


###########################################
# CONFIGURE SSH FOR GIT
###########################################

sudo -u student bash -c 'cat > /home/student/.ssh/config <<EOF
Host utility-git
    HostName 172.25.250.220
    User git
    IdentityFile /home/student/.ssh/id_ed25519
    StrictHostKeyChecking no
EOF'

sudo chmod 600 /home/student/.ssh/config

sudo chown student:student /home/student/.ssh/config


###########################################
# CONFIGURE GIT REMOTE
###########################################

sudo -u student git \
    -C /home/student/ansible \
    remote remove origin 2>/dev/null || true


sudo -u student git \
    -C /home/student/ansible \
    remote add origin \
    git@utility-git:/var/lib/git/ansible.git


###########################################
# TEST GIT UPLOAD
###########################################

echo "Testing Git upload..."

if [ ! -f /home/student/ansible/README.md ]; then

    sudo -u student bash -c \
        'echo "# RHEL 10 RHCE Practice Lab" > /home/student/ansible/README.md'

fi


sudo -u student git \
    -C /home/student/ansible \
    add .


if sudo -u student git \
    -C /home/student/ansible \
    diff --cached --quiet; then

    echo "Nothing new to commit."

else

    sudo -u student git \
        -C /home/student/ansible \
        commit -m "Initial RHEL 10 RHCE lab setup"

fi


# Push only if there is a commit
if sudo -u student git \
    -C /home/student/ansible \
    rev-parse HEAD >/dev/null 2>&1; then

    sudo -u student git \
        -C /home/student/ansible \
        branch -M main

    sudo -u student git \
        -C /home/student/ansible \
        push -u origin main --force

fi


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
echo "http://utility.lab.example.com/index/rhel-system-roles/"
echo ""
echo "Git Repository:"
echo "git@utility-git:/var/lib/git/ansible.git"
echo ""
echo "Local Ansible Directory:"
echo "/home/student/ansible"
echo ""
echo "======================================="
