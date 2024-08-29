#!/usr/bin/bash
set -o nounset -o errexit

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root. Please use sudo or run as root."
  exit 1
fi

WORKDIR=$(dirname "$(realpath $0)")
EMAIL=""
CLOUDFLARE_INI="/root/cloudflare.ini"
FQDN=$(hostname -f)
DOMAIN=$(echo $FQDN | sed -e 's/^[^.]*\.//')
WILDCARD_DOMAIN="*.$DOMAIN"

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

source /opt/certbot/bin/activate

# Obtain the certificate using certbot
certbot certonly --dns-cloudflare --dns-cloudflare-credentials "$CLOUDFLARE_INI" --dns-cloudflare-propagation-seconds \
    --email "$EMAIL" --agree-tos \
    -d "$WILDCARD_DOMAIN" -d "$DOMAIN" --non-interactive

deactivate

# Replace the FreeIPA certificate with the Let's Encrypt certificate
cp /var/lib/ipa/certs/httpd.crt /var/lib/ipa/certs/httpd.crt.bkp
cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem /var/lib/ipa/certs/httpd.crt
cp /etc/letsencrypt/live/$DOMAIN/privkey.pem /var/lib/ipa/private/httpd.key

# Set proper permissions
chown root:root /var/lib/ipa/private/httpd.key
chmod 600 /var/lib/ipa/private/httpd.key

# Restore SELinux contexts
restorecon -v /var/lib/ipa/certs/httpd.crt
restorecon -v /var/lib/ipa/private/httpd.key

# Restart httpd with the new certificate
if ! command -v service >/dev/null 2>&1; then
    systemctl start httpd
else
    service httpd start
fi
