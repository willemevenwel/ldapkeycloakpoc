#!/bin/bash

# test_all.sh
# Enhanced verification script for LDAP-Keycloak POC setup
# Tests all components configured by start_all.sh with debugging capabilities

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Parse arguments
DEBUG_MODE=false
REALM_NAME=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --debug)
            DEBUG_MODE=true
            shift
            ;;
        *)
            if [ -z "$REALM_NAME" ]; then
                REALM_NAME="$1"
            fi
            shift
            ;;
    esac
done

if [ -z "$REALM_NAME" ]; then
    echo -e "${BLUE}🔍 Testing LDAP-Keycloak setup (basic components)${NC}"
    echo -e "${YELLOW}⚠️  No realm name provided - skipping realm-specific tests${NC}"
    echo -e "${YELLOW}   To test a specific realm, run: ./test_all.sh <realm-name>${NC}"
else
    echo -e "${BLUE}🔍 Testing LDAP-Keycloak setup for realm: ${REALM_NAME}${NC}"
fi

if [ "$DEBUG_MODE" = true ]; then
    echo -e "${CYAN}🔧 Debug mode enabled - showing detailed logs and diagnostics${NC}"
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

# Test 2: Windows Git Bash path handling (if on Windows)
echo -e "${YELLOW}Testing platform-specific path handling...${NC}"

# Detect if we're on Windows (Git Bash/MSYS/Cygwin)
case "$(uname -s)" in
    MINGW*|CYGWIN*|MSYS*)
        echo -e "${CYAN}   Detected Windows environment - testing Git Bash path translation...${NC}"
        
        if [ -n "$ldap_running" ]; then
            # Test Windows Git Bash path translation issue
            docker exec ldap sh -c 'echo "test" > /tmp/windows_path_test.txt' >/dev/null 2>&1
            
            # Test old problematic path
            docker exec ldap cat /tmp/windows_path_test.txt >/dev/null 2>&1
            old_path_result=$?
            
            # Test fixed path
            docker exec ldap cat //tmp/windows_path_test.txt >/dev/null 2>&1
            new_path_result=$?
            
            # Cleanup
            docker exec ldap rm -f //tmp/windows_path_test.txt >/dev/null 2>&1
            
            if [ $old_path_result -eq 0 ] && [ $new_path_result -eq 0 ]; then
                check_result "pass" "Windows path handling" "both old and new paths work (WSL or compatible environment)"
            elif [ $old_path_result -ne 0 ] && [ $new_path_result -eq 0 ]; then
                check_result "pass" "Windows path handling" "fixed paths work correctly (Git Bash path translation resolved)"
                if [ "$DEBUG_MODE" = true ]; then
                    echo -e "${CYAN}   🔧 Path fix details: '/tmp/' → '//tmp/' prevents Git Bash translation${NC}"
                fi
            elif [ $old_path_result -eq 0 ] && [ $new_path_result -ne 0 ]; then
                check_result "fail" "Windows path handling" "old paths work but new paths don't - unusual configuration"
                echo -e "${YELLOW}   💡 Scripts may need further adjustment${NC}"
                if [ "$DEBUG_MODE" = true ]; then
                    echo -e "${YELLOW}   🔧 Debug: Old path result=$old_path_result, New path result=$new_path_result${NC}"
                fi
            else
                check_result "fail" "Windows path handling" "both paths fail - Docker/container issue"
                echo -e "${YELLOW}   💡 Check Docker Desktop settings and container status${NC}"
                if [ "$DEBUG_MODE" = true ]; then
                    echo -e "${YELLOW}   🔧 Debug: Old path result=$old_path_result, New path result=$new_path_result${NC}"
                fi
            fi
        else
            check_result "fail" "Windows path handling" "LDAP container not running - cannot test"
        fi
        ;;
    Darwin*)
        check_result "pass" "Platform detection" "macOS - no path translation issues expected"
        ;;
    Linux*)
        check_result "pass" "Platform detection" "Linux - no path translation issues expected"
        ;;
    *)
        check_result "pass" "Platform detection" "Unknown system - assuming Unix-like behavior"
        ;;
esac

echo ""

# Test 3: LDAP service accessibility
echo -e "${YELLOW}Testing ${CYAN}LDAP${NC} service...${NC}"

# First check if LDAP container is responsive
ldap_container_check=$(docker exec ldap echo "Container responsive" 2>/dev/null)
if [ $? -eq 0 ]; then
    check_result "pass" "${CYAN}LDAP${NC} container responsiveness" "container is responsive"
    
    # Show container logs in debug mode
    if [ "$DEBUG_MODE" = true ]; then
        echo -e "${CYAN}📋 Recent LDAP container logs (last 10 lines):${NC}"
        docker logs ldap --tail 10
        echo ""
    fi
    
    # Test basic LDAP service (anonymous)
    basic_test=$(docker exec ldap ldapsearch -x -H ldap://localhost:389 -b "" -s base 2>/dev/null)
    if [ $? -eq 0 ]; then
        check_result "pass" "${CYAN}LDAP${NC} basic service" "responding to anonymous queries"
    else
        check_result "fail" "${CYAN}LDAP${NC} basic service" "not responding"
    fi
    
    # Now test LDAP service connectivity with admin credentials
    ldap_test=$(docker exec ldap ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=min,dc=io" -w admin -b "dc=min,dc=io" -s base "(objectClass=*)" 2>/dev/null)
    if [ $? -eq 0 ]; then
        check_result "pass" "${CYAN}LDAP${NC} admin authentication" "cn=admin,dc=min,dc=io credentials work"
        
        # Check base DN structure in debug mode
        if [ "$DEBUG_MODE" = true ]; then
            echo -e "${CYAN}📋 Base DN structure:${NC}"
            docker exec ldap ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=min,dc=io" -w admin -b "dc=min,dc=io" -s base "(objectClass=*)"
            echo ""
        fi
    else
        check_result "fail" "${CYAN}LDAP${NC} admin authentication" "authentication failed"
        echo -e "${YELLOW}   💡 Try waiting longer for LDAP to fully initialize${NC}"
        if [ "$DEBUG_MODE" = true ]; then
            echo -e "${YELLOW}   🔧 Debug: Try manual test with:${NC}"
            echo -e "${YELLOW}      docker exec ldap ldapsearch -x -H ldap://localhost:389 -D \"cn=admin,dc=min,dc=io\" -w admin -b \"dc=min,dc=io\"${NC}"
        fi
    fi
else
    check_result "fail" "${CYAN}LDAP${NC} container responsiveness" "container not responding"
fi

# Test 4: LDAP users and groups
echo -e "${YELLOW}Testing ${CYAN}LDAP${NC} data import...${NC}"

# Check if OUs exist first
ou_users_test=$(docker exec ldap ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=min,dc=io" -w admin -b "ou=users,dc=min,dc=io" -s base "(objectClass=*)" 2>/dev/null)
if [ $? -eq 0 ]; then
    check_result "pass" "${CYAN}LDAP${NC} Users OU" "ou=users,dc=min,dc=io exists"
else
    check_result "fail" "${CYAN}LDAP${NC} Users OU" "ou=users,dc=min,dc=io not found"
fi

ou_groups_test=$(docker exec ldap ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=min,dc=io" -w admin -b "ou=groups,dc=min,dc=io" -s base "(objectClass=*)" 2>/dev/null)
if [ $? -eq 0 ]; then
    check_result "pass" "${CYAN}LDAP${NC} Groups OU" "ou=groups,dc=min,dc=io exists"
else
    check_result "fail" "${CYAN}LDAP${NC} Groups OU" "ou=groups,dc=min,dc=io not found"
fi

# Count users and groups
users_count=$(docker exec ldap ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=min,dc=io" -w admin -b "ou=users,dc=min,dc=io" "(objectClass=inetOrgPerson)" uid 2>/dev/null | grep -c "uid:" 2>/dev/null || echo 0)
groups_count=$(docker exec ldap ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=min,dc=io" -w admin -b "ou=groups,dc=min,dc=io" "(objectClass=posixGroup)" cn 2>/dev/null | grep -c "cn:" 2>/dev/null || echo 0)

# Clean up any newlines from the counts
users_count=$(echo "$users_count" | tr -d '\n\r')
groups_count=$(echo "$groups_count" | tr -d '\n\r')

if [ "$users_count" -gt 0 ]; then
    check_result "pass" "${CYAN}LDAP${NC} users imported" "$users_count users found"
    
    # Show user list in debug mode
    if [ "$DEBUG_MODE" = true ]; then
        echo -e "${CYAN}📋 Users in LDAP:${NC}"
        docker exec ldap ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=min,dc=io" -w admin -b "ou=users,dc=min,dc=io" "(objectClass=inetOrgPerson)" uid | grep "uid:" | cut -d' ' -f2
        echo ""
    fi
else
    check_result "fail" "${CYAN}LDAP${NC} users imported" "no users found"
fi

if [ "$groups_count" -gt 0 ]; then
    check_result "pass" "${CYAN}LDAP${NC} groups imported" "$groups_count groups found"
    
    # Show group list in debug mode
    if [ "$DEBUG_MODE" = true ]; then
        echo -e "${CYAN}📋 Groups in LDAP:${NC}"
        docker exec ldap ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=min,dc=io" -w admin -b "ou=groups,dc=min,dc=io" "(objectClass=posixGroup)" cn | grep "cn:" | cut -d' ' -f2
        echo ""
    fi
else
    check_result "fail" "${CYAN}LDAP${NC} groups imported" "no groups found"
fi

# Check admin user specifically
admin_user_test=$(docker exec ldap ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=min,dc=io" -w admin -b "dc=min,dc=io" "(uid=admin)" uid 2>/dev/null | grep -q "uid: admin")
if [ $? -eq 0 ]; then
    check_result "pass" "${CYAN}LDAP${NC} admin user" "admin user found in directory"
else
    check_result "fail" "${CYAN}LDAP${NC} admin user" "admin user not found"
fi

echo ""

# Test 5: Keycloak service accessibility
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

# Test 6: Keycloak realm exists
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
# Test 7: Get Keycloak admin token and test LDAP provider
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

# Test 8: LDAP Web Manager
echo -e "${YELLOW}Testing ${CYAN}LDAP${NC} Web Manager...${NC}"
webui_health=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 2>/dev/null)
if [ "$webui_health" = "200" ]; then
    check_result "pass" "${CYAN}LDAP${NC} Web Manager" "accessible on port 8080"
else
    check_result "fail" "${CYAN}LDAP${NC} Web Manager" "not accessible"
fi

# Test 9: Python Bastion functionality
echo -e "${YELLOW}Testing Python Bastion...${NC}"
python_test=$(docker exec python-bastion python --version 2>/dev/null)
if [ $? -eq 0 ]; then
    check_result "pass" "Python Bastion functionality" "Python $(echo $python_test | cut -d' ' -f2) ready"
else
    check_result "fail" "Python Bastion functionality" "Python not accessible"
fi

# Test 10: Generated LDIF files
echo -e "${YELLOW}Testing generated files...${NC}"
if [ -f "ldif/admins_only.ldif" ] && [ -s "ldif/admins_only.ldif" ]; then
    check_result "pass" "LDIF files generated" "admins_only.ldif present and non-empty"
else
    check_result "fail" "LDIF files generated" "admins_only.ldif missing or empty"
fi

# Test 11: Platform-specific information
if [ "$DEBUG_MODE" = true ]; then
    echo -e "${YELLOW}Platform and system information...${NC}"
    
    # Detect platform
    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
        check_result "pass" "Platform detection" "Windows detected"
        echo -e "${CYAN}   💡 Windows-specific recommendations:${NC}"
        echo -e "${CYAN}      • Ensure Docker Desktop uses Linux containers${NC}"
        echo -e "${CYAN}      • Consider increasing Docker memory to 4GB+${NC}"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        check_result "pass" "Platform detection" "macOS detected"
        echo -e "${CYAN}   💡 macOS works well with Docker Desktop${NC}"
    else
        check_result "pass" "Platform detection" "Linux detected"
        echo -e "${CYAN}   💡 Native Docker should work optimally${NC}"
    fi
    
    # Show Docker version
    docker_version=$(docker --version 2>/dev/null)
    if [ $? -eq 0 ]; then
        check_result "pass" "Docker version" "$docker_version"
    else
        check_result "fail" "Docker version" "Docker not accessible"
    fi
    
    echo ""
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
    echo -e "${YELLOW}💡 For detailed diagnostics, run: ./test_all.sh <realm-name> --debug${NC}"
fi

if [ -n "$REALM_NAME" ]; then
    echo -e "${YELLOW}💡 For detailed diagnostics, run: ./test_all.sh ${REALM_NAME} --debug${NC}"
fi

if [ "$DEBUG_MODE" = true ]; then
    echo ""
    echo -e "${CYAN}🔧 Quick troubleshooting commands:${NC}"
    echo -e "${CYAN}   • Restart LDAP: docker restart ldap${NC}"
    echo -e "${CYAN}   • Check logs: docker logs ldap${NC}"
    echo -e "${CYAN}   • Regenerate LDIF: docker exec python-bastion python python/csv_to_ldif.py data/admins.csv${NC}"
    echo -e "${CYAN}   • Full restart: docker-compose down && docker-compose up -d${NC}"
fi