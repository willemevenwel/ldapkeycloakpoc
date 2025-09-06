#!/bin/sh
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BLACK='\033[0;30m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
NC='\033[0m' # No Color

echo "Installing packages..."
apk add --no-cache openldap openldap-back-mdb openldap-clients python3

echo "Setting up directories..."
mkdir -p /var/lib/openldap/run /etc/openldap/slapd.d /var/lib/openldap/openldap-data

echo -e "Creating ${CYAN}LDAP${NC} configuration..."
cat > /etc/openldap/slapd.conf << 'EOF'
include /etc/openldap/schema/core.schema
include /etc/openldap/schema/cosine.schema
include /etc/openldap/schema/inetorgperson.schema
include /etc/openldap/schema/nis.schema

moduleload back_mdb

database mdb
suffix "dc=mycompany,dc=local"
rootdn "cn=admin,dc=mycompany,dc=local"
rootpw admin
directory /var/lib/openldap/openldap-data
maxsize 1073741824
EOF

echo "Setting permissions..."
chown -R ldap:ldap /var/lib/openldap

echo "Running CSV to LDIF conversion (admins only)..."
if [ -f /opt/import/admins.csv ]; then
  cd /opt/import && python3 csv_to_ldif.py admins.csv
  echo "Admin CSV conversion completed"
else
  echo "No admins CSV file found"
fi

echo -e "Starting ${CYAN}LDAP${NC} server..."
/usr/sbin/slapd -d 256 -f /etc/openldap/slapd.conf -h 'ldap://0.0.0.0:389' &
SLAPD_PID=$!

echo -e "Waiting for ${CYAN}LDAP${NC} server to start..."
sleep 5

echo "Importing admin users only..."
if [ -f /opt/output/admins_only.ldif ]; then
  ldapadd -x -D 'cn=admin,dc=mycompany,dc=local' -w admin -f /opt/output/admins_only.ldif
  echo "Admin import completed successfully!"
else
  echo "No admin LDIF file found to import"
fi

echo -e "${CYAN}LDAP${NC} server is ready!"
wait $SLAPD_PID
