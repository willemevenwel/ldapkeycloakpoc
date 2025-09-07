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
        if docker exec ldap ldapsearch -x -H ldap://localhost -b "dc=mycompany,dc=local" -D "cn=admin,dc=mycompany,dc=local" -w admin "(objectClass=dcObject)" > /dev/null 2>&1; then
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
    echo -e "❌ Error: ${WHITE}LDAP User Manager${NC} container 'ldap-manager' is not running."
    echo "Please start the system first with: ./start.sh"
    exit 1
fi

# Wait for LDAP to be fully ready
wait_for_ldap

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

copy_with_retry "ldif/additional_users.ldif" || exit 1

if [ -f "ldif/additional_users_modify.ldif" ]; then
    copy_with_retry "ldif/additional_users_modify.ldif" || exit 1
fi

echo -e "🔄 Adding new users and groups to ${CYAN}LDAP${NC}..."

# Function to execute LDAP commands (with proper exit code handling)
ldap_exec_safe() {
    local command_args="$@"
    
    echo -e "Executing: docker exec ldap $command_args"
    docker exec ldap $command_args
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

# Function for commands that might need retry (like connection issues)
ldap_exec_with_retry() {
    local command_args="$@"
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        echo -e "Attempt $attempt: docker exec ldap $command_args"
        docker exec ldap $command_args
        local exit_code=$?
        
        # Success or expected LDAP codes
        if [ $exit_code -eq 0 ] || [ $exit_code -eq 20 ] || [ $exit_code -eq 68 ]; then
            if [ $exit_code -eq 20 ]; then
                echo -e "ℹ️  Some values already exist (this is normal)"
            elif [ $exit_code -eq 68 ]; then
                echo -e "ℹ️  Some entries already exist (this is normal)"
            fi
            return 0
        fi
        
        # Only retry on actual connection/server errors (codes like 32, 49, 52, etc.)
        if [ $exit_code -eq 32 ] || [ $exit_code -eq 49 ] || [ $exit_code -eq 52 ] || [ $exit_code -eq 53 ]; then
            if [ $attempt -lt $max_attempts ]; then
                echo -e "⚠️  LDAP connection/server error (code $exit_code), retrying in 3 seconds..."
                sleep 3
            fi
        else
            echo -e "❌ LDAP command failed with exit code $exit_code (not retryable)"
            return $exit_code
        fi
        
        attempt=$((attempt + 1))
    done
    
    echo -e "⚠️  LDAP command failed after $max_attempts attempts with exit code $exit_code"
    return $exit_code
}

# Add new users and groups (ignore errors for existing entries)
ldap_exec_safe ldapadd -x -D "cn=admin,dc=mycompany,dc=local" -w admin -f /tmp/additional_users.ldif -c

# Update existing group memberships if modify file exists
if [ -f "ldif/additional_users_modify.ldif" ]; then
    echo "👥 Updating existing group memberships..."
    ldap_exec_safe ldapmodify -x -D "cn=admin,dc=mycompany,dc=local" -w admin -f /tmp/additional_users_modify.ldif -c
fi

# Verify the import was successful
echo -e "🔍 Verifying import..."
USER_COUNT=$(docker exec ldap ldapsearch -x -H ldap://localhost -b "ou=users,dc=mycompany,dc=local" -D "cn=admin,dc=mycompany,dc=local" -w admin "(objectClass=inetOrgPerson)" uid 2>/dev/null | grep "uid:" | wc -l)
GROUP_COUNT=$(docker exec ldap ldapsearch -x -H ldap://localhost -b "ou=groups,dc=mycompany,dc=local" -D "cn=admin,dc=mycompany,dc=local" -w admin "(objectClass=posixGroup)" cn 2>/dev/null | grep "cn:" | wc -l)

echo -e "📊 Import verification:"
echo -e "   • Users in LDAP: ${USER_COUNT}"
echo -e "   • Groups in LDAP: ${GROUP_COUNT}"

if [ "$USER_COUNT" -gt 1 ] && [ "$GROUP_COUNT" -gt 1 ]; then
    echo "✅ Additional users imported successfully!"
    IMPORT_SUCCESS=true
else
    echo "⚠️  Import may not have completed fully. Expected multiple users and groups."
    IMPORT_SUCCESS=false
fi

echo ""
echo -e "🌐 You can now access the updated ${CYAN}LDAP${NC}:"
echo -e "   - ${CYAN}LDAP${NC} Server: ldap://localhost:389"
echo "   - Web UI: http://localhost:8080"
echo "   - Login: admin/admin"
echo ""
echo "📊 To verify the import, you can run:"
echo "   ldapsearch -x -H ldap://localhost:389 -D 'cn=admin,dc=mycompany,dc=local' -w admin -b 'ou=users,dc=mycompany,dc=local' '(objectClass=inetOrgPerson)'"

# Clean up with retry
echo "🧹 Cleanup..."
cleanup_with_retry() {
    local file=$1
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if docker exec ldap rm -f "/tmp/$file" 2>/dev/null; then
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

# Exit with appropriate code
if [ "$IMPORT_SUCCESS" = true ]; then
    exit 0
else
    exit 1
fi
