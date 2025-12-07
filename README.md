🧪 RHCE Practice Lab Auto Setup (One-Command Deployment)

This repository provides a fully automated, one-command setup for an RHCE (Red Hat Certified Engineer) practice lab.
It automatically configures the lab environment, installs required services, deploys all RHCE practice papers, and prepares the system for training and evaluation — with zero manual configuration.

🚀 One-Line Installation Command

Run the following single command on your RHCE lab machine:

----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
bash -c 'curl -L https://raw.githubusercontent.com/codexchangee/rhce-practcie-lab-setup/main/a.sh | sudo bash'
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

✅ What This Script Does Automatically

Configures /etc/hosts with all RHCE lab nodes
Installs ansible.posix collection
Creates admin user on all lab machines using SSH
Installs and enables Apache (httpd)
Downloads all RHCE practice files directly from this GitHub repository
Deploys all content to:
/var/www/html/files
Sets correct Apache ownership and permissions
Restarts Apache automatically
Opens RHCE practice papers in the browser after setup

🌐 How to Access the RHCE Practice Papers

After the script finishes, open your browser and visit:
http://localhost/files


All RHCE practice content will be available there.

📂 Repository Structure
rhce-practcie-lab-setup/
├── a.sh        # Main RHCE auto-setup script
└── files/      # All RHCE practice papers, HTML files, images & resources



🔐 Default Lab Credentials
Username: admin
Password: root



✅ Fully Automated | One Command | Zero Manual Setup

This project is designed to eliminate manual lab setup and allow users to deploy a complete RHCE practice environment instantly using a single command.
