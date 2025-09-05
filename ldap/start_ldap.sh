#!/bin/sh
set -e

echo "Installing packages..."
apk add --no-cache openldap openldap-back-mdb openldap-clients python3

echo "Setting up directories..."
mkdir -p /var/lib/openldap/run /etc/openldap/slapd.d /var/lib/openldap/openldap-data

echo "Creating LDAP configuration..."
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

echo "Starting LDAP server..."
/usr/sbin/slapd -d 256 -f /etc/openldap/slapd.conf -h 'ldap://0.0.0.0:389' &
SLAPD_PID=$!

echo "Waiting for LDAP server to start..."
sleep 5

echo "Importing admin users only..."
if [ -f /opt/output/admins_only.ldif ]; then
  ldapadd -x -D 'cn=admin,dc=mycompany,dc=local' -w admin -f /opt/output/admins_only.ldif
  echo "Admin import completed successfully!"
else
  echo "No admin LDIF file found to import"
fi

echo "LDAP server is ready!"
wait $SLAPD_PID
