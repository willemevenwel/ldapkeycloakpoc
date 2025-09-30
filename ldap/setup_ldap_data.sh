#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}Setting up LDAP initial data...${NC}"

# Wait for LDAP server to be ready
echo "Waiting for LDAP server to be ready..."
timeout=90
counter=0

# First check if container is running
if ! docker ps | grep -q "ldap"; then
    echo -e "${RED}Error: LDAP container is not running${NC}"
    echo -e "${YELLOW}Please check 'docker ps' to verify container status${NC}"
    exit 1
fi

echo "LDAP container is running, checking LDAP service availability..."

while ! docker exec ldap ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=min,dc=io" -w admin -b "dc=min,dc=io" >/dev/null 2>&1; do
    if [ $counter -eq $timeout ]; then
        echo -e "${RED}Error: LDAP server did not respond within $timeout seconds${NC}"
        echo -e "${YELLOW}Container is running but LDAP service is not ready${NC}"
        echo -e "${YELLOW}Try running this command manually to debug:${NC}"
        echo -e "${YELLOW}docker exec ldap ldapsearch -x -H ldap://localhost:389 -D \"cn=admin,dc=min,dc=io\" -w admin -b \"dc=min,dc=io\"${NC}"
        exit 1
    fi
    echo "Waiting for LDAP service... ($counter/$timeout)"
    sleep 2
    counter=$((counter + 2))
done

echo -e "${GREEN}LDAP server is ready!${NC}"

# Copy and import LDIF files
echo -e "${CYAN}Importing LDIF data...${NC}"

if [ -f ldif/admins_only.ldif ]; then
    echo "Copying and importing admin users..."
    docker cp ldif/admins_only.ldif ldap:/tmp/admins_only.ldif
    # Use -c flag to continue on errors (like "already exists")
    docker exec ldap ldapadd -c -x -H ldap://localhost:389 -D 'cn=admin,dc=min,dc=io' -w admin -f /tmp/admins_only.ldif || true
    echo -e "${GREEN}Admin import completed successfully!${NC}"
else
    echo -e "${YELLOW}No admin LDIF file found to import${NC}"
fi

echo -e "${GREEN}LDAP initial data setup completed!${NC}"