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
# Usage: ./ldap/load_additional_users.sh [realm-name] [--defaults]

# Parse command line arguments
USE_DEFAULTS=false
REALM_NAME=""

for arg in "$@"; do
    case $arg in
        --defaults)
            USE_DEFAULTS=true
            shift
            ;;
        *)
            if [ -z "$REALM_NAME" ]; then
                REALM_NAME="$arg"
            fi
            shift
            ;;
    esac
done

echo -e "🔄 Loading additional users into ${CYAN}LDAP${NC}..."

# Function to wait for LDAP container to be ready
wait_for_ldap() {
    echo -e "⏳ Waiting for ${CYAN}LDAP${NC} container to be fully ready..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        # Check if container is running
        if ! docker ps | grep -q "ldap"; then
            echo -e "❌ Error: ${CYAN}LDAP${NC} container 'ldap' is not running."
            echo "Please start the system first with: ./start.sh"
            exit 1
        fi
        
        # Test LDAP connectivity
        if docker exec ldap ldapsearch -x -H ldap://localhost:389 -b "dc=min,dc=io" -D "cn=admin,dc=min,dc=io" -w admin "(objectClass=dcObject)" > /dev/null 2>&1; then
            echo -e "✅ ${CYAN}LDAP${NC} container is ready and responding"
            return 0
        fi
        
        echo -n "."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    echo -e "\n❌ Error: ${CYAN}LDAP${NC} container did not become ready within $((max_attempts * 2)) seconds"
    exit 1
}

# Check if containers are running and wait for them to be ready
if ! docker ps | grep -q "ldap"; then
    echo -e "❌ Error: ${CYAN}LDAP${NC} container 'ldap' is not running."
    echo "Please start the system first with: ./start.sh"
    exit 1
fi

if ! docker ps | grep -q "ldap-manager"; then
    echo -e "❌ Error: ${WHITE}${CYAN}LDAP${NC} Web Manager${NC} container 'ldap-manager' is not running."
    echo "Please start the system first with: ./start.sh"
    exit 1
fi

# Wait for LDAP to be fully ready
wait_for_ldap

echo -e "✅ ${CYAN}LDAP${NC} containers are running"

# Generate additional users LDIF

echo "📝 Generating LDIF for additional users using containerized Python..."
docker exec python-bastion python python-bastion/csv_to_ldif.py data/users.csv

if [ $? -ne 0 ]; then
    echo "❌ Error: Failed to generate additional users LDIF"
    exit 1
fi

# Check if there are users to import
if [ ! -f "ldif/users.ldif" ]; then
    echo "❌ Error: users.ldif file not found"
    exit 1
fi

# Check if the file has actual content (not just comments)
if ! grep -q "^dn:" ldif/users.ldif; then
    echo "ℹ️  No additional users to import (only admin users found in CSV)"
    echo "All users are already loaded as admins."
    exit 0
fi

echo "📋 Additional users LDIF content preview:"
echo "========================================"
head -20 ldif/users.ldif
echo "========================================"

# Copy LDIF files into container and import
echo -e "📥 Copying LDIF files to ${CYAN}LDAP${NC} container..."

# Function to copy files with retry
copy_with_retry() {
    local file=$1
    local max_attempts=5
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if docker cp "$file" ldap:/tmp/$(basename "$file"); then
            return 0
        fi
        echo -e "⚠️  Copy attempt $attempt failed, retrying..."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    echo -e "❌ Error: Failed to copy $file to container after $max_attempts attempts"
    return 1
}

copy_with_retry "ldif/users.ldif" || exit 1

if [ -f "ldif/group_assign.ldif" ]; then
    copy_with_retry "ldif/group_assign.ldif" || exit 1
fi

echo -e "🔄 Adding new users and groups to ${CYAN}LDAP${NC}..."

# Function to execute LDAP commands (with proper exit code handling)
ldap_exec_safe() {
    local ldap_command="$1"
    local ldap_file="$2"
    
    echo -e "Executing: docker exec ldap $ldap_command -f $ldap_file"
    docker exec ldap $ldap_command -f "$ldap_file"
    local exit_code=$?
    
    # Handle LDAP-specific exit codes
    case $exit_code in
        0)
            echo -e "✅ LDAP command completed successfully"
            return 0
            ;;
        20)
            echo -e "ℹ️  Some values already exist (this is normal for updates)"
            return 0
            ;;
        68)
            echo -e "ℹ️  Some entries already exist (this is normal for adds)"
            return 0
            ;;
        *)
            echo -e "❌ LDAP command failed with exit code $exit_code"
            return $exit_code
            ;;
    esac
}

# Add new users and groups (ignore errors for existing entries)
# Use double slash to prevent Git Bash on Windows from translating the path
ldap_exec_safe "ldapadd -x -D cn=admin,dc=min,dc=io -w admin -c" "//tmp/users.ldif"

# Update existing group memberships if modify file exists
if [ -f "ldif/group_assign.ldif" ]; then
    echo "👥 Updating existing group memberships..."
    # Use double slash to prevent Git Bash on Windows from translating the path
    ldap_exec_safe "ldapmodify -x -D cn=admin,dc=min,dc=io -w admin -c" "//tmp/group_assign.ldif"
fi

# Verify the import was successful
echo -e "🔍 Verifying import..."
USER_COUNT=$(docker exec ldap ldapsearch -x -H ldap://localhost:389 -b "ou=users,dc=min,dc=io" -D "cn=admin,dc=min,dc=io" -w admin "(objectClass=inetOrgPerson)" uid 2>/dev/null | grep "uid:" | wc -l)
GROUP_COUNT=$(docker exec ldap ldapsearch -x -H ldap://localhost:389 -b "ou=groups,dc=min,dc=io" -D "cn=admin,dc=min,dc=io" -w admin "(objectClass=posixGroup)" cn 2>/dev/null | grep "cn:" | wc -l)

echo -e "� Import verification:"
echo -e "   • Users in ${CYAN}LDAP${NC}:  ${USER_COUNT}"
echo -e "   • Groups in ${CYAN}LDAP${NC}: ${GROUP_COUNT}"

if [ "$USER_COUNT" -gt 1 ] && [ "$GROUP_COUNT" -gt 1 ]; then
    echo "✅ Additional users imported successfully!"
    IMPORT_SUCCESS=true
else
    echo "⚠️  Import may not have completed fully. Expected multiple users and groups."
    IMPORT_SUCCESS=false
fi

echo ""
echo -e "🌐 You can now access the updated ${CYAN}LDAP${NC}:"
echo -e "   ${CYAN}LDAP${NC} Protocol:            ${BLUE}ldap://localhost:389${NC}"
echo -e "   ${CYAN}LDAP${NC} Web Manager:         ${BLUE}http://localhost:8080${NC}"
echo -e "   ${CYAN}LDAP${NC} Web Manager Login:   ${YELLOW}admin / admin${NC}"
echo ""
echo "📊 To verify the import, you can run:"
echo -e "   ${YELLOW}ldapsearch -x -H ldap://localhost:389 -D 'cn=admin,dc=min,dc=io' -w admin -b 'ou=users,dc=min,dc=io' '(objectClass=inetOrgPerson)'${NC}"

# Clean up with retry
echo "🧹 Cleanup..."
cleanup_with_retry() {
    local file=$1
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        # Use double slash to prevent Git Bash path translation
        if docker exec ldap rm -f "//tmp/$file" 2>/dev/null; then
            return 0
        fi
        sleep 1
        attempt=$((attempt + 1))
    done
    return 1
}

cleanup_with_retry "additional_users.ldif"
if [ -f "ldif/additional_users_modify.ldif" ]; then
    cleanup_with_retry "additional_users_modify.ldif"
fi
echo "🧹 Cleanup completed"

# Prompt to run LDAP sync if import was successful
if [ "$IMPORT_SUCCESS" = true ]; then
    echo ""
    echo -e "${GREEN}🔧 Fixing LDAP password format for Keycloak compatibility...${NC}"
    # Run the password fix script to ensure cleartext passwords for Keycloak
    if [ -f "ldap/fix_ldap_passwords.sh" ]; then
        ./ldap/fix_ldap_passwords.sh
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ LDAP passwords fixed for Keycloak authentication${NC}"
        else
            echo -e "${YELLOW}⚠️  Password fix encountered issues, but continuing...${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  Password fix script not found at ldap/fix_ldap_passwords.sh${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}📋 Optional: Sync the new users and roles to Keycloak${NC}"
    echo -e "${YELLOW}   This will synchronize the newly added ${CYAN}LDAP${NC} users and roles with Keycloak${NC}"
    echo -e "${YELLOW}   Recommended to run this to make the new users available in Keycloak${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if [ "$USE_DEFAULTS" = true ]; then
        echo -e "${CYAN}Using default: Syncing ${CYAN}LDAP${NC} to Keycloak (--defaults mode)${NC}"
        run_sync="Y"
    else
        if [ -n "$REALM_NAME" ]; then
            echo -en "${CYAN}Do you want to sync ${CYAN}LDAP${NC} to Keycloak realm '${REALM_NAME}' now? (Y/n - default is Yes): ${NC}"
        else
            echo -en "${CYAN}Do you want to sync ${CYAN}LDAP${NC} to Keycloak now? (Y/n - default is Yes): ${NC}"
        fi
        read -r run_sync
    fi
    if [ "${run_sync}" = "N" ] || [ "${run_sync}" = "n" ]; then
        echo -e "${YELLOW}Skipped ${CYAN}LDAP${NC} sync. You can run it manually later with:${NC}"
        if [ -n "$REALM_NAME" ]; then
            echo -e "${YELLOW}   cd keycloak && ./sync_ldap.sh ${REALM_NAME}${NC}"
        else
            echo -e "${YELLOW}   cd keycloak && ./sync_ldap.sh <realm-name>${NC}"
        fi
    else
        # Use provided realm name or ask for it
        if [ -n "$REALM_NAME" ]; then
            realm_name="$REALM_NAME"
        else
            echo -en "${CYAN}Enter realm name to sync (e.g., wallmart, capgemini): ${NC}"
            read -r realm_name
        fi
        
        if [ -n "$realm_name" ]; then
            cd keycloak && ./sync_ldap.sh "$realm_name"
            echo ""
            echo -e "${GREEN}✅ ${CYAN}LDAP${NC} sync completed for realm: ${realm_name}${NC}"
        else
            echo -e "${RED}❌ No realm name provided, skipping sync${NC}"
        fi
    fi
    exit 0
else
    exit 1
fi
