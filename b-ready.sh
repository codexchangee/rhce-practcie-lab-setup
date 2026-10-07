#!/bin/bash
set -e

HOST_ENTRIES=(
"172.25.250.10    servera.lab.example.com    node1"
"172.25.250.11    serverb.lab.example.com    node2"
"172.25.250.220   utility.lab.example.com    node3"
"172.25.250.12    serverc.lab.example.com    node4"
"172.25.250.13    serverd.lab.example.com    node5"
)

echo "Backing up /etc/hosts..."
cp /etc/hosts /etc/hosts.bak.$(date +%s) 2>/dev/null || true
for entry in "${HOST_ENTRIES[@]}"; do
    if ! grep -Fqx "$entry" /etc/hosts; then
        echo "$entry" >> /etc/hosts
    fi
done

echo "Installing required packages on workstation..."
dnf install -y httpd git curl tar sshpass policycoreutils-python-utils rhel-system-roles ansible-core
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
useradd -m admin 2>/dev/null || true
echo "admin:root" | chpasswd
echo "admin ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/admin
chmod 440 /etc/sudoers.d/admin
EOF
done

systemctl enable --now httpd

GITHUB_USER="codexchangee"
GITHUB_REPO="rhce-practcie-lab-setup"
GITHUB_BRANCH="main"
URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}/archive/refs/heads/${GITHUB_BRANCH}.tar.gz"

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

echo "Downloading files from GitHub..."
curl -fL "$URL" -o "$WORKDIR/repo.tar.gz"
tar -xzf "$WORKDIR/repo.tar.gz" -C "$WORKDIR"
EXTRACTED=$(find "$WORKDIR" -maxdepth 1 -type d -name "${GITHUB_REPO}-*" | head -n1)

if [ -z "$EXTRACTED" ] || [ ! -d "$EXTRACTED" ]; then
    echo "ERROR: GitHub repository extraction failed."
    exit 1
fi

echo "Setting up web content..."
rm -rf /var/www/html/*
mkdir -p /var/www/html/files
mkdir -p /var/www/html/index/rhel-system-roles

echo "Copying HTML files..."
find "$EXTRACTED/test" -type f -name "*.html" -exec cp {} /var/www/html/ \;

echo "Copying lab files..."
if [ -d "$EXTRACTED/files" ]; then
    find "$EXTRACTED/files" -maxdepth 1 -type f \
        ! -name "redhat-rhel_system_roles-1.19.3.tar.gz" \
        -exec cp {} /var/www/html/files/ \;
fi

echo "Setting up RHEL System Roles..."
SYSTEM_ROLES_ARCHIVE="$EXTRACTED/files/redhat-rhel_system_roles-1.19.3.tar.gz"

if [ -f "$SYSTEM_ROLES_ARCHIVE" ]; then
    rm -rf /var/www/html/index/rhel-system-roles/*
    tar -xzf "$SYSTEM_ROLES_ARCHIVE" \
        -C /var/www/html/index/rhel-system-roles \
        --strip-components=1
else
    echo "Archive 1.19.3 is not currently present in the GitHub files directory."
    echo "Using the installed RHEL System Roles package instead."
    ROLE_SOURCE="/usr/share/ansible/collections/ansible_collections/redhat/rhel_system_roles"
    if [ ! -d "$ROLE_SOURCE" ]; then
        echo "ERROR: RHEL System Roles collection was not installed."
        exit 1
    fi
    rm -rf /var/www/html/index/rhel-system-roles/*
    cp -a "$ROLE_SOURCE"/. /var/www/html/index/rhel-system-roles/
fi

STUDENT_USER="${SUDO_USER:-student}"
STUDENT_HOME="/home/${STUDENT_USER}"
ANSIBLE_DIR="${STUDENT_HOME}/ansible"

mkdir -p "$ANSIBLE_DIR/roles"
chown -R "$STUDENT_USER:$STUDENT_USER" "$ANSIBLE_DIR"

echo "Preparing Git server on utility..."
sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no root@172.25.250.220 <<'EOF'
dnf install -y git
mkdir -p /var/lib/git/ansible.git
if [ ! -d /var/lib/git/ansible.git/objects ]; then
    rm -rf /var/lib/git/ansible.git
    git init --bare /var/lib/git/ansible.git
fi
if [ -x /usr/libexec/git-core/git-receive-pack ]; then
    ln -sf /usr/libexec/git-core/git-receive-pack /usr/local/bin/git-receive-pack
fi
if [ -x /usr/libexec/git-core/git-upload-pack ]; then
    ln -sf /usr/libexec/git-core/git-upload-pack /usr/local/bin/git-upload-pack
fi
EOF

echo "Preparing student SSH key..."
install -d -m 700 -o "$STUDENT_USER" -g "$STUDENT_USER" "$STUDENT_HOME/.ssh"
if [ ! -f "$STUDENT_HOME/.ssh/id_ed25519" ]; then
    runuser -u "$STUDENT_USER" -- ssh-keygen -q -t ed25519 \
        -N "" -f "$STUDENT_HOME/.ssh/id_ed25519"
fi
PUBKEY=$(cat "$STUDENT_HOME/.ssh/id_ed25519.pub")

sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no root@172.25.250.220 \
"mkdir -p /root/.ssh && chmod 700 /root/.ssh && touch /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys && grep -qxF '$PUBKEY' /root/.ssh/authorized_keys || echo '$PUBKEY' >> /root/.ssh/authorized_keys"

echo "Preparing Git repository in $ANSIBLE_DIR..."
runuser -u "$STUDENT_USER" -- bash -c "
set -e
cd '$ANSIBLE_DIR'
if [ ! -d .git ]; then git init; fi
git config user.name 'student'
git config user.email 'student@lab.example.com'
git branch -M main
git remote remove origin 2>/dev/null || true
git remote add origin 'root@172.25.250.220:/var/lib/git/ansible.git'
git config remote.origin.receivepack /usr/libexec/git-core/git-receive-pack
git config remote.origin.uploadpack /usr/libexec/git-core/git-upload-pack
if [ ! -f README.md ] && [ -z \"\$(git log -1 --oneline 2>/dev/null || true)\" ]; then
    printf '%s\n' '# RHCE Practice Ansible Repository' > README.md
    git add README.md
    git commit -m 'Initialize RHCE Ansible repository'
fi
git push -u origin main
"

echo "Setting permissions and SELinux..."
chown -R apache:apache /var/www/html
chmod -R 755 /var/www/html
semanage fcontext -a -t httpd_sys_content_t "/var/www/html(/.*)?" 2>/dev/null || \
semanage fcontext -m -t httpd_sys_content_t "/var/www/html(/.*)?"
restorecon -Rv /var/www/html
systemctl restart httpd

echo "Fixing node1..."
sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no root@172.25.250.10 \
    "dnf remove -y python3-pyOpenSSL || true"

echo "Fixing node3..."
sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no root@172.25.250.220 \
    "dnf remove -y nginx || true"

echo
echo "Checking Git..."
runuser -u "$STUDENT_USER" -- bash -c "cd '$ANSIBLE_DIR' && git status && git remote -v"

echo
echo "Checking RHEL System Roles..."
ls -ld /var/www/html/index/rhel-system-roles
find /var/www/html/index/rhel-system-roles -maxdepth 2 -type d | head -20

xdg-open http://localhost 2>/dev/null || true
xdg-open http://localhost/files 2>/dev/null || true
xdg-open http://localhost/index/rhel-system-roles/ 2>/dev/null || true

echo
echo "======================================="
echo "Environment Ready"
echo "======================================="
echo "Main UI:           http://localhost"
echo "Lab Files:        http://localhost/files"
echo "System Roles:     http://localhost/index/rhel-system-roles/"
echo "Ansible directory: /home/${STUDENT_USER}/ansible"
echo "Git remote:        root@172.25.250.220:/var/lib/git/ansible.git"
echo "======================================="
