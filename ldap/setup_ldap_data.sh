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

# Try to connect with the correct admin DN - MinIO OpenLDAP uses cn=admin,dc=min,dc=io
while ! docker exec ldap ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=min,dc=io" -w admin -b "dc=min,dc=io" >/dev/null 2>&1; do
    if [ $counter -eq $timeout ]; then
        echo -e "${RED}Error: LDAP server did not respond within $timeout seconds${NC}"
        echo -e "${YELLOW}Container is running but LDAP service is not ready${NC}"
        echo -e "${YELLOW}Debugging LDAP connectivity...${NC}"
        
        # Try basic container connectivity
        echo -e "${CYAN}Checking container logs:${NC}"
        docker logs ldap --tail 10
        
        echo -e "${CYAN}Trying alternative connection methods:${NC}"
        # Try without authentication first
        if docker exec ldap ldapsearch -x -H ldap://localhost:389 -b "" -s base >/dev/null 2>&1; then
            echo -e "${GREEN}✓ Basic LDAP service is responding${NC}"
        else
            echo -e "${RED}✗ LDAP service is not responding at all${NC}"
        fi
        
        echo -e "${YELLOW}Manual debug command:${NC}"
        echo -e "${YELLOW}docker exec ldap ldapsearch -x -H ldap://localhost:389 -D \"cn=admin,dc=min,dc=io\" -w admin -b \"dc=min,dc=io\"${NC}"
        exit 1
    fi
    echo "Waiting for LDAP service... ($counter/$timeout)"
    sleep 3  # Increased sleep for Windows compatibility
    counter=$((counter + 3))
done

echo -e "${GREEN}LDAP server is ready!${NC}"

# Copy and import LDIF files
echo -e "${CYAN}Importing LDIF data...${NC}"

if [ -f ldif/admins_only.ldif ]; then
    echo "Copying and importing admin users..."
    docker cp ldif/admins_only.ldif ldap:/tmp/admins_only.ldif
    
    # Import LDIF and capture output for debugging
    echo -e "${CYAN}Importing admin LDIF...${NC}"
    # Use double slash to prevent Git Bash on Windows from translating the path
    if docker exec ldap ldapadd -c -x -H ldap://localhost:389 -D 'cn=admin,dc=min,dc=io' -w admin -f //tmp/admins_only.ldif; then
        echo -e "${GREEN}✓ Admin LDIF imported successfully${NC}"
    else
        echo -e "${YELLOW}⚠️  LDIF import had warnings (possibly duplicate entries)${NC}"
    fi
    
    # Validate that admin user was created
    echo -e "${CYAN}Validating admin user creation...${NC}"
    if docker exec ldap ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=min,dc=io" -w admin -b "dc=min,dc=io" "(uid=admin)" uid >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Admin user 'admin' found in LDAP${NC}"
    else
        echo -e "${RED}✗ Admin user 'admin' not found in LDAP${NC}"
        echo -e "${YELLOW}Debugging: Searching for all users...${NC}"
        docker exec ldap ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=min,dc=io" -w admin -b "ou=users,dc=min,dc=io" "(objectClass=inetOrgPerson)" uid
        exit 1
    fi
    
    # Validate that admin group was created
    echo -e "${CYAN}Validating admin group creation...${NC}"
    if docker exec ldap ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=min,dc=io" -w admin -b "dc=min,dc=io" "(cn=admins)" cn >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Admin group 'admins' found in LDAP${NC}"
    else
        echo -e "${RED}✗ Admin group 'admins' not found in LDAP${NC}"
        echo -e "${YELLOW}Debugging: Searching for all groups...${NC}"
        docker exec ldap ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=min,dc=io" -w admin -b "ou=groups,dc=min,dc=io" "(objectClass=posixGroup)" cn
        exit 1
    fi
    
    echo -e "${GREEN}✅ Admin import completed and validated successfully!${NC}"
else
    echo -e "${RED}❌ No admin LDIF file found to import${NC}"
    echo -e "${YELLOW}Expected file: ldif/admins_only.ldif${NC}"
    echo -e "${YELLOW}Please ensure CSV to LDIF conversion ran successfully${NC}"
    exit 1
fi

echo -e "${GREEN}LDAP initial data setup completed!${NC}"