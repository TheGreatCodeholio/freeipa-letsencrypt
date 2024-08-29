#!/usr/bin/bash
set -o nounset -o errexit

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root. Please use sudo or run as root."
  exit 1
fi

WORKDIR=$(dirname "$(realpath $0)")
EMAIL="ian@icarey.net"
CLOUDFLARE_INI="/root/cloudflare.ini"
FQDN=$(hostname -f)
DOMAIN=$(echo $FQDN | sed -e 's/^[^.]*\.//')
WILDCARD_DOMAIN="*.$DOMAIN"

CERTS=("isrgrootx1.pem" "isrg-root-x2.pem" "lets-encrypt-r3.pem" "lets-encrypt-e1.pem" "lets-encrypt-r4.pem" "lets-encrypt-e2.pem")

# Download and install the Let's Encrypt CA certificates
if [ ! -d "/etc/ssl/$FQDN" ]; then
    mkdir -p "/etc/ssl/$FQDN"
fi

for CERT in "${CERTS[@]}"; do
    if command -v wget &> /dev/null; then
        wget -O "/etc/ssl/$FQDN/$CERT" "https://letsencrypt.org/certs/$CERT"
    elif command -v curl &> /dev/null; then
        curl -o "/etc/ssl/$FQDN/$CERT" "https://letsencrypt.org/certs/$CERT"
    fi
    ipa-cacert-manage install "/etc/ssl/$FQDN/$CERT"
done

ipa-certupdate

### cron
# skip renewal if the cert is still valid for more than 30 days
if [ "${1:-renew}" != "--first-time" ]
then
    end_timestamp=`date +%s --date="$(openssl x509 -enddate -noout -in /var/lib/ipa/certs/httpd.crt | cut -d= -f2)"`
    now_timestamp=`date +%s`
    let diff=($end_timestamp-$now_timestamp)/86400
    if [ "$diff" -gt "30" ]; then
        exit 0
    fi
fi

# Stop httpd before renewal
if ! command -v service >/dev/null 2>&1; then
    systemctl stop httpd
else
    service httpd stop
fi

# Obtain the certificate using certbot
certbot certonly --dns-cloudflare --dns-cloudflare-credentials "$CLOUDFLARE_INI" \
    --email "$EMAIL" --agree-tos \
    --domain "$WILDCARD_DOMAIN" --domain "$DOMAIN" --non-interactive

# Replace the FreeIPA certificate with the Let's Encrypt certificate
cp /var/lib/ipa/certs/httpd.crt /var/lib/ipa/certs/httpd.crt.bkp
cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem /var/lib/ipa/certs/httpd.crt
cp /etc/letsencrypt/live/$DOMAIN/privkey.pem /var/lib/ipa/private/httpd.key

# Restore SELinux contexts
restorecon -v /var/lib/ipa/certs/httpd.crt
restorecon -v /var/lib/ipa/private/httpd.key

# Restart httpd with the new certificate
if ! command -v service >/dev/null 2>&1; then
    systemctl start httpd
else
    service httpd start
fi
