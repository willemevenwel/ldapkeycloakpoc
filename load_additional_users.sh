#!/bin/bash

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

# load_additional_users.sh
# Script to manually load additional users into LDAP after startup

echo -e "🔄 Loading additional users into ${CYAN}LDAP${NC}..."

# Check if containers are running
if ! docker ps | grep -q "ldap"; then
    echo -e "❌ Error: ${CYAN}LDAP${NC} container 'ldap' is not running."
    echo "Please start the system first with: ./start.sh"
    exit 1
fi

if ! docker ps | grep -q "ldap-manager"; then
    echo -e "❌ Error: ${WHITE}LDAP User Manager${NC} container 'ldap-manager' is not running."
    echo "Please start the system first with: ./start.sh"
    exit 1
fi

echo -e "✅ ${CYAN}LDAP${NC} containers are running"

# Generate additional users LDIF
echo "📝 Generating LDIF for additional users..."
python3 csv_to_ldif.py data/users.csv

if [ $? -ne 0 ]; then
    echo "❌ Error: Failed to generate additional users LDIF"
    exit 1
fi

# Check if there are users to import
if [ ! -f "ldif/additional_users.ldif" ]; then
    echo "❌ Error: additional_users.ldif file not found"
    exit 1
fi

# Check if the file has actual content (not just comments)
if ! grep -q "^dn:" ldif/additional_users.ldif; then
    echo "ℹ️  No additional users to import (only admin users found in CSV)"
    echo "All users are already loaded as admins."
    exit 0
fi

echo "📋 Additional users LDIF content preview:"
echo "========================================"
head -20 ldif/additional_users.ldif
echo "========================================"

# Copy LDIF files into container and import
echo -e "📥 Copying LDIF files to ${CYAN}LDAP${NC} container..."
docker cp ldif/additional_users.ldif ldap:/tmp/additional_users.ldif

if [ -f "ldif/additional_users_modify.ldif" ]; then
    docker cp ldif/additional_users_modify.ldif ldap:/tmp/additional_users_modify.ldif
fi

if [ $? -ne 0 ]; then
    echo "❌ Error: Failed to copy LDIF files to container"
    exit 1
fi

echo -e "🔄 Adding new users and groups to ${CYAN}LDAP${NC}..."

# Add new users and groups (ignore errors for existing groups)
docker exec ldap ldapadd -x -D 'cn=admin,dc=mycompany,dc=local' -w admin -f /tmp/additional_users.ldif -c

# Update existing group memberships if modify file exists
if [ -f "ldif/additional_users_modify.ldif" ]; then
    echo "👥 Updating existing group memberships..."
    docker exec ldap ldapmodify -x -D 'cn=admin,dc=mycompany,dc=local' -w admin -f /tmp/additional_users_modify.ldif -c
fi

if [ $? -eq 0 ]; then
    echo "✅ Additional users imported successfully!"
    echo ""
    echo -e "🌐 You can now access the updated ${CYAN}LDAP${NC}:"
    echo -e "   - ${CYAN}LDAP${NC} Server: ldap://localhost:389"
    echo "   - Web UI: http://localhost:8080"
    echo "   - Login: admin/admin"
    echo ""
    echo "📊 To verify the import, you can run:"
    echo "   ldapsearch -x -H ldap://localhost:389 -D 'cn=admin,dc=mycompany,dc=local' -w admin -b 'ou=users,dc=mycompany,dc=local' '(objectClass=inetOrgPerson)'"
else
    echo "⚠️  Import completed with some warnings (this is normal for group updates)"
    echo -e "✅ Additional users should now be available in ${CYAN}LDAP${NC}"
fi

# Clean up
docker exec ldap rm -f /tmp/additional_users.ldif
if [ -f "ldif/additional_users_modify.ldif" ]; then
    docker exec ldap rm -f /tmp/additional_users_modify.ldif
fi
echo "🧹 Cleanup completed"
