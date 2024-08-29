#!/usr/bin/bash
set -o nounset -o errexit

if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root. Please use sudo or run as root."
  exit 1
fi

FQDN=$(hostname -f)
WORKDIR=$(dirname "$(realpath $0)")
CERTS=("isrgrootx1.pem" "isrg-root-x2.pem" "lets-encrypt-r3.pem" "lets-encrypt-e1.pem" "lets-encrypt-r4.pem" "lets-encrypt-e2.pem")

sed -i "s/server.example.test/$FQDN/g" $WORKDIR/ipa-httpd.cnf

# Install system dependencies
dnf install -y python3 augeas-libs

# Remove any existing certbot installation
dnf remove -y certbot || yum remove -y certbot

# Set up a Python virtual environment for certbot
python3 -m venv /opt/certbot/
/opt/certbot/bin/pip install --upgrade pip

# Install Certbot in the virtual environment
/opt/certbot/bin/pip install certbot

# Prepare the Certbot command
ln -s /opt/certbot/bin/certbot /usr/bin/certbot

# Install the correct DNS plugin for Cloudflare
/opt/certbot/bin/pip install certbot-dns-cloudflare

# Create directory for storing SSL certificates if it doesn't exist
if [ ! -d "/etc/ssl/$FQDN" ]; then
    mkdir -p "/etc/ssl/$FQDN"
fi

# Download and install Let's Encrypt root certificates
for CERT in "${CERTS[@]}"; do
    if command -v wget &> /dev/null; then
        wget -O "/etc/ssl/$FQDN/$CERT" "https://letsencrypt.org/certs/$CERT"
    elif command -v curl &> /dev/null; then
        curl -o "/etc/ssl/$FQDN/$CERT" "https://letsencrypt.org/certs/$CERT"
    fi
    ipa-cacert-manage install "/etc/ssl/$FQDN/$CERT"
done

ipa-certupdate

# Run the renewal script for the first time
"$WORKDIR/renew-le.sh" --first-time
