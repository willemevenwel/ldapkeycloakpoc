#!/bin/bash

# test_all.sh
# Verification script for LDAP-Keycloak POC setup
# Tests all components configured by start_all.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Get realm name from parameter
REALM_NAME="$1"

if [ -z "$REALM_NAME" ]; then
    echo -e "${BLUE}🔍 Testing LDAP-Keycloak setup (basic components)${NC}"
    echo -e "${YELLOW}⚠️  No realm name provided - skipping realm-specific tests${NC}"
    echo -e "${YELLOW}   To test a specific realm, run: ./test_all.sh <realm-name>${NC}"
else
    echo -e "${BLUE}🔍 Testing LDAP-Keycloak setup for realm: ${REALM_NAME}${NC}"
fi
echo ""

# Function to print check results
check_result() {
    local status=$1
    local message=$2
    local details=$3
    
    if [ "$status" = "pass" ]; then
        echo -e "✅ $message - $details"
    else
        echo -e "🚨 $message - $details"
    fi
}

# Test 1: Docker containers running
echo -e "${YELLOW}Testing Docker containers...${NC}"
ldap_running=$(docker ps --filter "name=ldap" --filter "status=running" -q)
keycloak_running=$(docker ps --filter "name=keycloak" --filter "status=running" -q)
ldap_manager_running=$(docker ps --filter "name=ldap-manager" --filter "status=running" -q)
python_bastion_running=$(docker ps --filter "name=python-bastion" --filter "status=running" -q)

if [ -n "$ldap_running" ]; then
    check_result "pass" "${CYAN}LDAP${NC} container" "running"
else
    check_result "fail" "${CYAN}LDAP${NC} container" "not running"
fi

if [ -n "$keycloak_running" ]; then
    check_result "pass" "${MAGENTA}Keycloak${NC} container" "running"
else
    check_result "fail" "${MAGENTA}Keycloak${NC} container" "not running"
fi

if [ -n "$ldap_manager_running" ]; then
    check_result "pass" "${CYAN}LDAP${NC} Manager container" "running"
else
    check_result "fail" "${CYAN}LDAP${NC} Manager container" "not running"
fi

if [ -n "$python_bastion_running" ]; then
    check_result "pass" "Python Bastion container" "running"
else
    check_result "fail" "Python Bastion container" "not running"
fi

echo ""

# Test 2: LDAP service accessibility
echo -e "${YELLOW}Testing ${CYAN}LDAP${NC} service...${NC}"

# First check if LDAP container is responsive
ldap_container_check=$(docker exec ldap echo "Container responsive" 2>/dev/null)
if [ $? -eq 0 ]; then
    check_result "pass" "${CYAN}LDAP${NC} container responsiveness" "container is responsive"
    
    # Now test LDAP service connectivity with timeout
    ldap_test=$(timeout 10s docker exec ldap ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=mycompany,dc=local" -w admin -b "dc=mycompany,dc=local" -s base "(objectClass=*)" 2>/dev/null)
    if [ $? -eq 0 ]; then
        check_result "pass" "${CYAN}LDAP${NC} service connectivity" "accessible on port 389"
    else
        check_result "fail" "${CYAN}LDAP${NC} service connectivity" "not accessible or timed out"
        echo -e "${YELLOW}   💡 Try waiting longer for LDAP to fully initialize${NC}"
    fi
else
    check_result "fail" "${CYAN}LDAP${NC} container responsiveness" "container not responding"
fi

# Test 3: LDAP users and groups
users_count=$(timeout 10s docker exec ldap ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=mycompany,dc=local" -w admin -b "ou=users,dc=mycompany,dc=local" "(objectClass=inetOrgPerson)" uid 2>/dev/null | grep -c "uid:")
groups_count=$(timeout 10s docker exec ldap ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=mycompany,dc=local" -w admin -b "ou=groups,dc=mycompany,dc=local" "(objectClass=posixGroup)" cn 2>/dev/null | grep -c "cn:")

if [ "$users_count" -gt 0 ]; then
    check_result "pass" "${CYAN}LDAP${NC} users imported" "$users_count users found"
else
    check_result "fail" "${CYAN}LDAP${NC} users imported" "no users found"
fi

if [ "$groups_count" -gt 0 ]; then
    check_result "pass" "${CYAN}LDAP${NC} groups imported" "$groups_count groups found"
else
    check_result "fail" "${CYAN}LDAP${NC} groups imported" "no groups found"
fi

echo ""

# Test 4: Keycloak service accessibility
echo -e "${YELLOW}Testing ${MAGENTA}Keycloak${NC} service...${NC}"
keycloak_health=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8090/health/ready 2>/dev/null)
if [ "$keycloak_health" = "200" ]; then
    check_result "pass" "${MAGENTA}Keycloak${NC} service health" "ready and accessible"
else
    # Try alternative health check
    keycloak_alt=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8090/realms/master 2>/dev/null)
    if [ "$keycloak_alt" = "200" ]; then
        check_result "pass" "${MAGENTA}Keycloak${NC} service health" "accessible via master realm"
    else
        check_result "fail" "${MAGENTA}Keycloak${NC} service health" "not accessible"
    fi
fi

# Test 5: Keycloak realm exists
if [ -n "$REALM_NAME" ]; then
    echo -e "${YELLOW}Testing ${MAGENTA}Keycloak${NC} realm...${NC}"
    realm_check=$(curl -s "http://localhost:8090/realms/${REALM_NAME}" 2>/dev/null)
    if echo "$realm_check" | grep -q "\"realm\":\"${REALM_NAME}\""; then
        check_result "pass" "${MAGENTA}Keycloak${NC} realm '${REALM_NAME}'" "exists and accessible"
    else
        check_result "fail" "${MAGENTA}Keycloak${NC} realm '${REALM_NAME}'" "not found or not accessible"
    fi
else
    echo -e "${YELLOW}⚠️  Skipping ${MAGENTA}Keycloak${NC} realm tests - no realm name provided${NC}"
fi

echo ""
# Test 6: Get Keycloak admin token and test LDAP provider
if [ -n "$REALM_NAME" ]; then
    echo -e "${YELLOW}Testing ${MAGENTA}Keycloak${NC} ${CYAN}LDAP${NC} integration...${NC}"
    admin_token=$(curl -s -X POST "http://localhost:8090/realms/${REALM_NAME}/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=admin-${REALM_NAME}" \
        -d "password=admin-${REALM_NAME}" \
        -d "grant_type=password" \
        -d "client_id=admin-cli" 2>/dev/null | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)

    if [ -n "$admin_token" ]; then
        check_result "pass" "${MAGENTA}Keycloak${NC} realm admin authentication" "token obtained successfully"
        
        # Test LDAP provider exists
        ldap_providers=$(curl -s -X GET "http://localhost:8090/admin/realms/${REALM_NAME}/components?type=org.keycloak.storage.UserStorageProvider" \
            -H "Authorization: Bearer ${admin_token}" 2>/dev/null)
        
        if echo "$ldap_providers" | grep -q "ldap-provider"; then
            check_result "pass" "${MAGENTA}Keycloak${NC} ${CYAN}LDAP${NC} provider" "configured and present"
        else
            check_result "fail" "${MAGENTA}Keycloak${NC} ${CYAN}LDAP${NC} provider" "not found"
        fi
        
        # Test synced users count
        users_response=$(curl -s -X GET "http://localhost:8090/admin/realms/${REALM_NAME}/users?max=100" \
            -H "Authorization: Bearer ${admin_token}" 2>/dev/null)
        synced_users=$(echo "$users_response" | grep -o '"username"' | wc -l)
        
        if [ "$synced_users" -gt 0 ]; then
            check_result "pass" "${MAGENTA}Keycloak${NC} synced users" "$synced_users users synced from ${CYAN}LDAP${NC}"
        else
            check_result "fail" "${MAGENTA}Keycloak${NC} synced users" "no users synced"
        fi
        
    else
        check_result "fail" "${MAGENTA}Keycloak${NC} realm admin authentication" "could not obtain token"
    fi
else
    echo -e "${YELLOW}⚠️  Skipping ${MAGENTA}Keycloak${NC} ${CYAN}LDAP${NC} integration tests - no realm name provided${NC}"
fi

echo ""

# Test 7: LDAP Web Manager
echo -e "${YELLOW}Testing ${CYAN}LDAP${NC} Web Manager...${NC}"
webui_health=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 2>/dev/null)
if [ "$webui_health" = "200" ]; then
    check_result "pass" "${CYAN}LDAP${NC} Web Manager" "accessible on port 8080"
else
    check_result "fail" "${CYAN}LDAP${NC} Web Manager" "not accessible"
fi

# Test 8: Python Bastion functionality
echo -e "${YELLOW}Testing Python Bastion...${NC}"
python_test=$(docker exec python-bastion python --version 2>/dev/null)
if [ $? -eq 0 ]; then
    check_result "pass" "Python Bastion functionality" "Python $(echo $python_test | cut -d' ' -f2) ready"
else
    check_result "fail" "Python Bastion functionality" "Python not accessible"
fi

# Test 9: Generated LDIF files
echo -e "${YELLOW}Testing generated files...${NC}"
if [ -f "ldif/admins_only.ldif" ] && [ -s "ldif/admins_only.ldif" ]; then
    check_result "pass" "LDIF files generated" "admins_only.ldif present and non-empty"
else
    check_result "fail" "LDIF files generated" "admins_only.ldif missing or empty"
fi

echo ""
echo -e "${BLUE}🎯 Test Summary Complete${NC}"
if [ -n "$REALM_NAME" ]; then
    echo -e "${GREEN}🌐 Access your setup:${NC}"
    echo -e "${GREEN}   • ${MAGENTA}Keycloak${NC} Admin     : ${CYAN}http://localhost:8090/admin/${REALM_NAME}/console/${NC}"
    echo -e "${GREEN}   • Realm URL          : ${CYAN}http://localhost:8090/realms/${REALM_NAME}${NC}"
    echo -e "${GREEN}   • ${CYAN}LDAP${NC} Web Manager   : ${CYAN}http://localhost:8080${NC}"
else
    echo -e "${GREEN}🌐 Access basic setup:${NC}"
    echo -e "${GREEN}   • ${MAGENTA}Keycloak${NC} Master    : ${CYAN}http://localhost:8090/admin/master/console/${NC}"
    echo -e "${GREEN}   • ${CYAN}LDAP${NC} Web Manager   : ${CYAN}http://localhost:8080${NC}"
    echo ""
    echo -e "${YELLOW}💡 To test a specific realm, run: ./test_all.sh <realm-name>${NC}"
fi