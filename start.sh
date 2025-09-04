#!/bin/sh

mkdir -p ldif

echo "Building my-ldap-user-manager Docker image..."
(cd ldap-user-manager && docker build -t my-ldap-user-manager .)

docker-compose up -d

# Print service URLs
LDAP_URL="ldap://localhost:389"
WEBUI_URL="http://localhost:8080"
echo "\nService URLs:"
echo "  LDAP server: $LDAP_URL"
echo "  LDAP Web UI: $WEBUI_URL"
echo "  Admin DN: cn=admin,dc=mycompany,dc=local"
echo "  Admin password: admin"
