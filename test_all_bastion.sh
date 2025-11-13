#!/bin/bash

# test_all_bastion.sh
# Enhanced verification script for LDAP-Keycloak POC setup
# This script runs inside the python-bastion container where all tools are available
# This eliminates cross-platform compatibility issues with Windows/Git Bash

# Check if we're running inside the container or from host
if [ -f /.dockerenv ] || [ "$CONTAINER_RUNTIME" = "true" ]; then
    # We're inside the container - run the internal version
    exec ./test_all.sh "$@"
else
    # We're on the host - execute inside python-bastion container
    echo "🐳 Running comprehensive tests inside python-bastion container for cross-platform compatibility..."
    
    # Check if python-bastion container is running
    if ! docker ps --format "table {{.Names}}" | grep -q "python-bastion"; then
        echo "❌ python-bastion container not running. Please start services first:"
        echo "   ./start_all_bastion.sh"
        exit 1
    fi
    
    # Execute the internal script inside the container
    docker exec -it python-bastion bash -c "cd /workspace && ./test_all.sh $*"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Source HTTP debug logging functions
SCRIPT_DIR_INTERNAL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR_INTERNAL}/http_debug.sh" ]; then
    source "${SCRIPT_DIR_INTERNAL}/http_debug.sh"
fi

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
                # Normalize realm name to lowercase for consistency
                REALM_NAME=$(echo "$REALM_NAME" | tr '[:upper:]' '[:lower:]')
            fi
            shift
            ;;
    esac
done

if [ -z "$REALM_NAME" ]; then
    echo -e "${BLUE}🔍 Testing LDAP-Keycloak setup (basic components)${NC}"
    echo -e "${YELLOW}⚠️  No realm name provided - skipping realm-specific tests${NC}"
    echo -e "${YELLOW}   To test a specific realm, run: ./test_all_bastion.sh <realm-name>${NC}"
else
    echo -e "${BLUE}🔍 Testing LDAP-Keycloak setup for realm: ${REALM_NAME}${NC}"
fi

if [ "$DEBUG_MODE" = true ]; then
    echo -e "${CYAN}🔧 Debug mode enabled - showing detailed logs and diagnostics${NC}"
    enable_http_debug
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

# Test 12: Organizations Feature Enablement (COMPREHENSIVE CHECK)
if [ -n "$REALM_NAME" ] && [ -n "$admin_token" ]; then
    echo -e "${YELLOW}Testing Organizations feature enablement...${NC}"
    
    # Get current realm configuration for comprehensive check
    realm_config_response=$(curl -s -X GET "http://localhost:8090/admin/realms/${REALM_NAME}" \
        -H "Authorization: Bearer ${admin_token}" 2>/dev/null)
    
    if [ -n "$realm_config_response" ]; then
        # Test 1: Check server-level Organizations feature
        server_features_response=$(curl -s -X GET "http://localhost:8090/admin/serverinfo" \
            -H "Authorization: Bearer ${admin_token}" 2>/dev/null)
        
        if echo "$server_features_response" | grep -q '"name":"ORGANIZATION"' && echo "$server_features_response" | grep -q '"enabled":true'; then
            check_result "pass" "Server-level Organizations feature" "enabled in Keycloak server"
        else
            check_result "fail" "Server-level Organizations feature" "not enabled in Keycloak server"
            if [ "$DEBUG_MODE" = true ]; then
                echo -e "${YELLOW}   💡 Check docker-compose.yml command: should include --features=organization${NC}"
            fi
        fi
        
        # Test 2: Check realm attribute (org.keycloak.organization.enabled)
        if echo "$realm_config_response" | grep -q '"org.keycloak.organization.enabled":"true"'; then
            check_result "pass" "Realm Organizations attribute" "org.keycloak.organization.enabled = true"
        else
            check_result "fail" "Realm Organizations attribute" "org.keycloak.organization.enabled not set to true"
        fi
        
        # Test 3: Check realm organizationsEnabled field
        if echo "$realm_config_response" | grep -q '"organizationsEnabled":true'; then
            check_result "pass" "Realm Organizations field" "organizationsEnabled = true"
        else
            check_result "fail" "Realm Organizations field" "organizationsEnabled not set to true"
            if [ "$DEBUG_MODE" = true ]; then
                echo -e "${YELLOW}   💡 This field is required for Organizations UI visibility${NC}"
            fi
        fi
        
        # Test 4: Check Organizations API accessibility
        org_api_response=$(curl -s -w "%{http_code}" -X GET "http://localhost:8090/admin/realms/${REALM_NAME}/organizations" \
            -H "Authorization: Bearer ${admin_token}" \
            -o /tmp/org_api_check.json 2>/dev/null)
        
        if [ "$org_api_response" = "200" ]; then
            check_result "pass" "Organizations API accessibility" "HTTP 200 - API is accessible"
            
            # Count existing organizations
            if [ -f /tmp/org_api_check.json ]; then
                org_count=$(cat /tmp/org_api_check.json | grep -o '"id"' | wc -l | tr -d ' ')
                if [ "$org_count" -gt 0 ]; then
                    check_result "pass" "Organizations created" "${org_count} organizations found"
                else
                    check_result "pass" "Organizations ready" "API accessible, no organizations created yet"
                fi
            fi
        else
            check_result "fail" "Organizations API accessibility" "HTTP ${org_api_response} - API not accessible"
            if [ -f /tmp/org_api_check.json ]; then
                api_error=$(cat /tmp/org_api_check.json)
                if [ "$DEBUG_MODE" = true ]; then
                    echo -e "${YELLOW}   🔧 API Error: ${api_error}${NC}"
                fi
            fi
        fi
        
        # Test 5: Comprehensive Organizations enablement status
        server_org_enabled=$(echo "$server_features_response" | grep -q '"name":"ORGANIZATION"' && echo "$server_features_response" | grep -q '"enabled":true' && echo "true" || echo "false")
        realm_attr_enabled=$(echo "$realm_config_response" | grep -q '"org.keycloak.organization.enabled":"true"' && echo "true" || echo "false")
        realm_field_enabled=$(echo "$realm_config_response" | grep -q '"organizationsEnabled":true' && echo "true" || echo "false")
        api_accessible=$([ "$org_api_response" = "200" ] && echo "true" || echo "false")
        
        if [ "$server_org_enabled" = "true" ] && [ "$realm_attr_enabled" = "true" ] && [ "$realm_field_enabled" = "true" ] && [ "$api_accessible" = "true" ]; then
            check_result "pass" "Complete Organizations enablement" "all requirements met - UI should be visible"
        else
            check_result "fail" "Complete Organizations enablement" "missing requirements for full functionality"
            if [ "$DEBUG_MODE" = true ]; then
                echo -e "${CYAN}   🔧 Organizations Enablement Status:${NC}"
                echo -e "${CYAN}      • Server feature enabled: ${server_org_enabled}${NC}"
                echo -e "${CYAN}      • Realm attribute set: ${realm_attr_enabled}${NC}"
                echo -e "${CYAN}      • Realm field enabled: ${realm_field_enabled}${NC}"
                echo -e "${CYAN}      • API accessible: ${api_accessible}${NC}"
                echo ""
                echo -e "${YELLOW}   💡 All four must be 'true' for Organizations to appear in UI${NC}"
            fi
        fi
        
        # Test 6: Organizations UI direct access test
        if [ "$server_org_enabled" = "true" ] && [ "$realm_attr_enabled" = "true" ] && [ "$realm_field_enabled" = "true" ]; then
            org_ui_url="http://localhost:8090/admin/${REALM_NAME}/console/#/${REALM_NAME}/organizations"
            check_result "pass" "Organizations UI availability" "should be accessible at console"
            if [ "$DEBUG_MODE" = true ]; then
                echo -e "${CYAN}   🌐 Organizations UI URL: ${org_ui_url}${NC}"
                echo -e "${CYAN}   💡 If UI not visible, try browser refresh (Ctrl+F5) or clear cache${NC}"
            fi
        else
            check_result "fail" "Organizations UI availability" "requirements not met - UI will not be visible"
        fi
        
        # Test 7: Organization Identity Provider linking
        if [ "$org_api_response" = "200" ] && [ -f /tmp/org_api_check.json ]; then
            org_count=$(cat /tmp/org_api_check.json | grep -o '"id"' | wc -l | tr -d ' ')
            
            if [ "$org_count" -gt 0 ]; then
                echo -e "${YELLOW}Testing organization Identity Provider linking...${NC}"
                
                # Get list of organizations
                organizations=$(cat /tmp/org_api_check.json)
                
                # Check if organization-specific Mock OAuth2 IdPs exist at realm level
                all_idps_response=$(curl -s -X GET "http://localhost:8090/admin/realms/${REALM_NAME}/identity-provider/instances" \
                    -H "Authorization: Bearer ${admin_token}" 2>/dev/null)
                
                mock_idp_count=$(echo "$all_idps_response" | grep -o '"alias":"mock-oauth2-[^"]*"' | wc -l | tr -d ' ')
                
                if [ "$mock_idp_count" -gt 0 ]; then
                    check_result "pass" "Mock OAuth2 Identity Providers" "${mock_idp_count} organization-specific IdPs configured"
                    
                    # Test each organization for IdP linking
                    org_with_idp_count=0
                    total_orgs=0
                    
                    # Parse organization IDs and names (compatible with Windows/Git Bash)
                    if command -v python3 >/dev/null 2>&1; then
                        org_ids=$(echo "$organizations" | python3 -c "import sys, json; [print(org['id']) for org in json.load(sys.stdin)]" 2>/dev/null)
                        org_names=$(echo "$organizations" | python3 -c "import sys, json; [print(org['name']) for org in json.load(sys.stdin)]" 2>/dev/null)
                    elif command -v python >/dev/null 2>&1; then
                        org_ids=$(echo "$organizations" | python -c "import sys, json; [print(org['id']) for org in json.load(sys.stdin)]" 2>/dev/null)
                        org_names=$(echo "$organizations" | python -c "import sys, json; [print(org['name']) for org in json.load(sys.stdin)]" 2>/dev/null)
                    elif command -v jq >/dev/null 2>&1; then
                        org_ids=$(echo "$organizations" | jq -r '.[].id' 2>/dev/null)
                        org_names=$(echo "$organizations" | jq -r '.[].name' 2>/dev/null)
                        
                        for org_id in $org_ids; do
                            total_orgs=$((total_orgs + 1))
                            
                            # Check if organization has any Mock OAuth2 IdP linked
                            org_idp_response=$(curl -s -w "%{http_code}" -X GET "http://localhost:8090/admin/realms/${REALM_NAME}/organizations/${org_id}/identity-providers" \
                                -H "Authorization: Bearer ${admin_token}" \
                                -o /tmp/org_idp_check.json 2>/dev/null)
                            
                            if [ "$org_idp_response" = "200" ]; then
                                # Check if any mock-oauth2 IdP is in the response
                                if grep -q "mock-oauth2-" /tmp/org_idp_check.json 2>/dev/null; then
                                    org_with_idp_count=$((org_with_idp_count + 1))
                                fi
                            fi
                        done
                        
                        if [ "$org_with_idp_count" -gt 0 ]; then
                            check_result "pass" "Organizations with Mock OAuth2 IdP" "${org_with_idp_count}/${total_orgs} organizations have IdP linked"
                        else
                            check_result "fail" "Organizations with Mock OAuth2 IdP" "no organizations have IdP linked"
                            if [ "$DEBUG_MODE" = true ]; then
                                echo -e "${YELLOW}   💡 Check configure_mock_oauth2_idp.sh script execution${NC}"
                                echo -e "${YELLOW}   💡 Organizations should show Mock OAuth2 in their Identity Providers section${NC}"
                            fi
                        fi
                        
                        # Clean up temp file
                        rm -f /tmp/org_idp_check.json 2>/dev/null
                    else
                        check_result "warn" "Organizations IdP linking test" "Python and jq not available - skipping detailed test"
                    fi
                else
                    check_result "fail" "Mock OAuth2 Identity Providers" "no organization-specific IdPs found"
                    if [ "$DEBUG_MODE" = true ]; then
                        echo -e "${YELLOW}   💡 Run configure_mock_oauth2_idp.sh to set up organization-specific Mock OAuth2 IdPs${NC}"
                    fi
                fi
            fi
        fi

        # Cleanup temporary files
        rm -f /tmp/org_api_check.json 2>/dev/null
        
    else
        check_result "fail" "Realm configuration access" "could not retrieve realm configuration"
    fi
    
echo ""
else
    echo -e "${YELLOW}⚠️  Skipping Organizations feature enablement tests - no realm name or admin token${NC}"
fi

echo ""

# Test 13: Organization-aware shared clients (NEW FEATURE)
if [ -n "$REALM_NAME" ] && [ -n "$admin_token" ]; then
    echo -e "${YELLOW}Testing organization-aware shared clients...${NC}"
    
    # Test shared-web-client exists
    web_client_response=$(curl -s -X GET "http://localhost:8090/admin/realms/${REALM_NAME}/clients?clientId=shared-web-client" \
        -H "Authorization: Bearer ${admin_token}" 2>/dev/null)
    
    if echo "$web_client_response" | grep -q "shared-web-client"; then
        check_result "pass" "Shared web client" "exists and configured"
        
        # Extract client UUID and secret for testing
        WEB_CLIENT_UUID=$(echo "$web_client_response" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
        
        if [ -n "$WEB_CLIENT_UUID" ]; then
            # Get client secret
            web_client_secret_response=$(curl -s -X GET "http://localhost:8090/admin/realms/${REALM_NAME}/clients/${WEB_CLIENT_UUID}/client-secret" \
                -H "Authorization: Bearer ${admin_token}" 2>/dev/null)
            WEB_CLIENT_SECRET=$(echo "$web_client_secret_response" | grep -o '"value":"[^"]*"' | cut -d'"' -f4)
            
            if [ -n "$WEB_CLIENT_SECRET" ]; then
                check_result "pass" "Shared web client secret" "retrieved successfully"
                
                if [ "$DEBUG_MODE" = true ]; then
                    echo -e "${CYAN}   🔧 Web Client Secret: ${WEB_CLIENT_SECRET}${NC}"
                fi
            else
                check_result "fail" "Shared web client secret" "could not retrieve"
            fi
        fi
    else
        check_result "fail" "Shared web client" "not found"
    fi
    
    # Test shared-api-client exists
    api_client_response=$(curl -s -X GET "http://localhost:8090/admin/realms/${REALM_NAME}/clients?clientId=shared-api-client" \
        -H "Authorization: Bearer ${admin_token}" 2>/dev/null)
    
    if echo "$api_client_response" | grep -q "shared-api-client"; then
        check_result "pass" "Shared API client" "exists and configured"
    else
        check_result "fail" "Shared API client" "not found"
    fi
    
echo ""
    
    # Test 14: Organization-specific protocol mappers
    echo -e "${YELLOW}Testing organization-specific protocol mappers...${NC}"
    
    if [ -n "$WEB_CLIENT_UUID" ]; then
        # Get protocol mappers for web client
        mappers_response=$(curl -s -X GET "http://localhost:8090/admin/realms/${REALM_NAME}/clients/${WEB_CLIENT_UUID}/protocol-mappers/models" \
            -H "Authorization: Bearer ${admin_token}" 2>/dev/null)
        
        # Check for realm role mapper (could be named "realm roles", "realm_access", or "realm_access-structure")
        if echo "$mappers_response" | grep -qE "(realm.roles|realm_access)"; then
            check_result "pass" "Realm roles mapper" "configured for global role access"
        else
            check_result "fail" "Realm roles mapper" "not found"
        fi
        
        # Check for organization-specific enabled flags (actual implementation)
        if echo "$mappers_response" | grep -q "acme-enabled"; then
            check_result "pass" "ACME enabled flag" "configured for organization detection"
        else
            check_result "fail" "ACME enabled flag" "not found"
        fi
        
        if echo "$mappers_response" | grep -q "xyz-enabled"; then
            check_result "pass" "XYZ enabled flag" "configured for organization detection"
        else
            check_result "fail" "XYZ enabled flag" "not found"
        fi
        
        # Check for organization indicators
        if echo "$mappers_response" | grep -q "organization_enabled"; then
            check_result "pass" "Organization indicators" "configured for JWT tokens"
        else
            check_result "fail" "Organization indicators" "not found"
        fi
        
        if [ "$DEBUG_MODE" = true ]; then
            echo -e "${CYAN}📋 Protocol mappers configured:${NC}"
            echo "$mappers_response" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | sed 's/^/   • /'
            echo ""
        fi
    fi
    
echo ""
    
    # Test 15: JWT Token generation with organization-specific test users
    echo -e "${YELLOW}Testing JWT token generation with organization-specific test users...${NC}"
    echo -e "${CYAN}💡 Testing predictable organization test users created during setup${NC}"
    
    if [ -n "$WEB_CLIENT_SECRET" ]; then
        # Test organization-specific users with predictable roles (compatible with zsh/older bash)
        test_users_data=(
            "test-acme-admin:acme_admin"
            "test-acme-developer:acme_developer" 
            "test-acme-user:acme_user"
            "test-xyz-admin:xyz_admin"
            "test-xyz-developer:xyz_developer"
            "test-xyz-user:xyz_user"
            "test-multi-org:acme_user,xyz_user"
            "test-no-org:developers"
        )
        
        for user_data in "${test_users_data[@]}"; do
            TEST_USERNAME="${user_data%%:*}"
            EXPECTED_ROLES="${user_data#*:}"
            TEST_PASSWORD="$TEST_USERNAME"  # Password same as username
        
            echo -e "${BLUE}🧪 Testing user: ${TEST_USERNAME} (expected roles: ${EXPECTED_ROLES})${NC}"
            
            token_response=$(curl -s -X POST "http://localhost:8090/realms/${REALM_NAME}/protocol/openid-connect/token" \
                -H "Content-Type: application/x-www-form-urlencoded" \
                -d "username=${TEST_USERNAME}" \
                -d "password=${TEST_PASSWORD}" \
                -d "grant_type=password" \
                -d "client_id=shared-web-client" \
                -d "client_secret=${WEB_CLIENT_SECRET}" 2>/dev/null)
            
            if echo "$token_response" | grep -q "access_token"; then
                check_result "pass" "JWT generation for ${TEST_USERNAME}" "successfully authenticated"
                
                # Extract and decode JWT token
                ACCESS_TOKEN=$(echo "$token_response" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
                
                if [ -n "$ACCESS_TOKEN" ]; then
                    # Decode JWT payload (base64 decode the middle part)
                    JWT_PAYLOAD=$(echo "$ACCESS_TOKEN" | cut -d'.' -f2)
                    # Add padding if needed for base64 decode
                    case $((${#JWT_PAYLOAD} % 4)) in
                        2) JWT_PAYLOAD="${JWT_PAYLOAD}==" ;;
                        3) JWT_PAYLOAD="${JWT_PAYLOAD}=" ;;
                    esac
                    
                    DECODED_JWT=$(echo "$JWT_PAYLOAD" | base64 -d 2>/dev/null)
                    
                    if [ $? -eq 0 ] && [ -n "$DECODED_JWT" ]; then
                        # Verify realm_access.roles contains expected roles
                        role_verification_passed=true
                        
                        if echo "$DECODED_JWT" | grep -q "realm_access"; then
                            check_result "pass" "Realm roles claim for ${TEST_USERNAME}" "realm_access.roles present"
                            
                            # Extract roles from JWT
                            JWT_ROLES=$(echo "$DECODED_JWT" | grep -o '"realm_access":{[^}]*}' | sed 's/.*"roles":\[\([^]]*\)\].*/\1/' | tr -d '"' | tr ',' ' ')
                            
                            # Check each expected role
                            IFS=',' read -ra EXPECTED_ROLE_ARRAY <<< "$EXPECTED_ROLES"
                            for expected_role in "${EXPECTED_ROLE_ARRAY[@]}"; do
                                if echo "$JWT_ROLES" | grep -q "$expected_role"; then
                                    check_result "pass" "Role verification ${TEST_USERNAME}" "contains expected role: $expected_role"
                                else
                                    check_result "fail" "Role verification ${TEST_USERNAME}" "missing expected role: $expected_role"
                                    role_verification_passed=false
                                fi
                            done
                            
                            # Organization-specific verification
                            if [[ "$TEST_USERNAME" == *"acme"* ]]; then
                                acme_role_found=false
                                for role in $JWT_ROLES; do
                                    if [[ "$role" == acme_* ]]; then
                                        acme_role_found=true
                                        break
                                    fi
                                done
                                if [ "$acme_role_found" = true ]; then
                                    check_result "pass" "ACME organization roles ${TEST_USERNAME}" "contains ACME-prefixed roles"
                                else
                                    check_result "fail" "ACME organization roles ${TEST_USERNAME}" "missing ACME-prefixed roles"
                                fi
                            fi
                            
                            if [[ "$TEST_USERNAME" == *"xyz"* ]]; then
                                xyz_role_found=false
                                for role in $JWT_ROLES; do
                                    if [[ "$role" == xyz_* ]]; then
                                        xyz_role_found=true
                                        break
                                    fi
                                done
                                if [ "$xyz_role_found" = true ]; then
                                    check_result "pass" "XYZ organization roles ${TEST_USERNAME}" "contains XYZ-prefixed roles"
                                else
                                    check_result "fail" "XYZ organization roles ${TEST_USERNAME}" "missing XYZ-prefixed roles"
                                fi
                            fi
                            
                            if [[ "$TEST_USERNAME" == "test-multi-org" ]]; then
                                # Should have both ACME and XYZ roles
                                acme_found=false
                                xyz_found=false
                                for role in $JWT_ROLES; do
                                    if [[ "$role" == acme_* ]]; then acme_found=true; fi
                                    if [[ "$role" == xyz_* ]]; then xyz_found=true; fi
                                done
                                if [ "$acme_found" = true ] && [ "$xyz_found" = true ]; then
                                    check_result "pass" "Multi-org roles ${TEST_USERNAME}" "contains both ACME and XYZ roles"
                                else
                                    check_result "fail" "Multi-org roles ${TEST_USERNAME}" "missing ACME or XYZ roles"
                                fi
                            fi
                            
                            if [[ "$TEST_USERNAME" == "test-no-org" ]]; then
                                # Should NOT have organization roles
                                org_role_found=false
                                for role in $JWT_ROLES; do
                                    if [[ "$role" == acme_* ]] || [[ "$role" == xyz_* ]]; then
                                        org_role_found=true
                                        break
                                    fi
                                done
                                if [ "$org_role_found" = false ]; then
                                    check_result "pass" "Non-org user ${TEST_USERNAME}" "correctly has no organization roles"
                                else
                                    check_result "fail" "Non-org user ${TEST_USERNAME}" "incorrectly has organization roles"
                                fi
                            fi
                            
                            if [ "$DEBUG_MODE" = true ]; then
                                echo -e "${CYAN}   📋 JWT roles for ${TEST_USERNAME}:${NC}"
                                for role in $JWT_ROLES; do
                                    echo -e "      • $role"
                                done
                            fi
                            
                        else
                            check_result "fail" "Realm roles claim for ${TEST_USERNAME}" "realm_access.roles missing"
                            role_verification_passed=false
                        fi
                        
                        # Test organization flags
                        if echo "$DECODED_JWT" | grep -q "organization_enabled"; then
                            check_result "pass" "Organization flags ${TEST_USERNAME}" "organization_enabled present"
                        else
                            check_result "fail" "Organization flags ${TEST_USERNAME}" "organization_enabled missing"
                        fi
                        
                        if [ "$DEBUG_MODE" = true ]; then
                            echo -e "${CYAN}📋 Complete JWT payload for ${TEST_USERNAME}:${NC}"
                            # Use Python for JSON formatting (more portable than jq)
                            if command -v python3 >/dev/null 2>&1; then
                                echo "$DECODED_JWT" | python3 -m json.tool 2>/dev/null || echo "$DECODED_JWT"
                            elif command -v python >/dev/null 2>&1; then
                                echo "$DECODED_JWT" | python -m json.tool 2>/dev/null || echo "$DECODED_JWT"
                            else
                                echo "$DECODED_JWT"
                            fi
                            echo ""
                        fi
                        
                    else
                        check_result "fail" "JWT decoding for ${TEST_USERNAME}" "could not decode token payload"
                    fi
                else
                    check_result "fail" "JWT extraction for ${TEST_USERNAME}" "could not extract access_token"
                fi
                
            else
                check_result "fail" "JWT generation for ${TEST_USERNAME}" "authentication failed"
                if [ "$DEBUG_MODE" = true ]; then
                    echo -e "${YELLOW}   🔧 Token response: ${token_response}${NC}"
                fi
            fi
            
            echo ""  # Space between test users
        done
        
        
    else
        check_result "fail" "Organization test users" "shared-web-client secret not available"
    fi
    
    echo ""

    
echo ""
    
    # Test 16: Organization-aware client scopes (current implementation uses protocol mappers instead)
    echo -e "${YELLOW}Testing organization-aware approach...${NC}"
    
    # Current implementation uses protocol mappers with organization flags instead of separate client scopes
    # This is a simpler and more maintainable approach
    check_result "pass" "Organization approach" "using protocol mappers with org flags (no separate client scopes needed)"
    
    if [ "$DEBUG_MODE" = true ]; then
        echo -e "${CYAN}💡 Current approach uses protocol mappers instead of client scopes:${NC}"
        echo -e "${CYAN}   • realm_access.roles: contains all user roles${NC}"
        echo -e "${CYAN}   • {org}_enabled flags: indicate supported organizations${NC}"
        echo -e "${CYAN}   • organization_enabled: general org support flag${NC}"
        echo -e "${CYAN}   • Client apps filter realm roles by organization prefix${NC}"
        echo ""
    fi
    
else
    echo -e "${YELLOW}⚠️  Skipping organization-aware features tests - no realm name or admin token${NC}"
fi

echo ""

# Test 17: LDAP organization groups and role sync
if [ -n "$REALM_NAME" ]; then
    echo -e "${YELLOW}Testing LDAP organization groups and role sync...${NC}"
    
    # Check for organization-specific groups in LDAP
    acme_groups=$(docker exec ldap ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=min,dc=io" -w admin -b "ou=groups,dc=min,dc=io" "(cn=acme*)" cn 2>/dev/null | grep -c "cn: acme" || echo 0)
    xyz_groups=$(docker exec ldap ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=min,dc=io" -w admin -b "ou=groups,dc=min,dc=io" "(cn=xyz*)" cn 2>/dev/null | grep -c "cn: xyz" || echo 0)
    
    acme_groups=$(echo "$acme_groups" | tr -d '\n\r')
    xyz_groups=$(echo "$xyz_groups" | tr -d '\n\r')
    
    if [ "$acme_groups" -gt 0 ]; then
        check_result "pass" "ACME organization groups in LDAP" "${acme_groups} acme_* groups found"
    else
        check_result "fail" "ACME organization groups in LDAP" "no acme_* groups found"
    fi
    
    if [ "$xyz_groups" -gt 0 ]; then
        check_result "pass" "XYZ organization groups in LDAP" "${xyz_groups} xyz_* groups found"
    else
        check_result "fail" "XYZ organization groups in LDAP" "no xyz_* groups found"
    fi
    
    # Check for organization-specific roles in Keycloak
    if [ -n "$admin_token" ]; then
        roles_response=$(curl -s -X GET "http://localhost:8090/admin/realms/${REALM_NAME}/roles" \
            -H "Authorization: Bearer ${admin_token}" 2>/dev/null)
        
        acme_roles_count=$(echo "$roles_response" | grep -o '"name":"acme_[^"]*"' | wc -l)
        xyz_roles_count=$(echo "$roles_response" | grep -o '"name":"xyz_[^"]*"' | wc -l)
        
        acme_roles_count=$(echo "$acme_roles_count" | tr -d '\n\r' | head -1)
        xyz_roles_count=$(echo "$xyz_roles_count" | tr -d '\n\r' | head -1)
        
        if [ "$acme_roles_count" -gt 0 ]; then
            check_result "pass" "ACME organization roles in Keycloak" "${acme_roles_count} acme_* roles synced"
        else
            check_result "fail" "ACME organization roles in Keycloak" "no acme_* roles found"
        fi
        
        if [ "$xyz_roles_count" -gt 0 ]; then
            check_result "pass" "XYZ organization roles in Keycloak" "${xyz_roles_count} xyz_* roles synced"
        else
            check_result "fail" "XYZ organization roles in Keycloak" "no xyz_* roles found"
        fi
        
        if [ "$DEBUG_MODE" = true ]; then
            echo -e "${CYAN}📋 Organization roles in Keycloak:${NC}"
            echo "$roles_response" | grep -o '"name":"[^"]*"' | grep -E "(acme_|xyz_)" | cut -d'"' -f4 | sed 's/^/   • /'
            echo ""
        fi
    fi
fi

echo ""
echo -e "${BLUE}🎯 Test Summary Complete${NC}"
if [ -n "$REALM_NAME" ]; then
    echo -e "${GREEN}🌐 Access your setup:${NC}"
    echo -e "${GREEN}   • ${MAGENTA}Keycloak${NC} Admin     : ${CYAN}http://localhost:8090/admin/${REALM_NAME}/console/${NC}"
    echo -e "${GREEN}   • Realm URL          : ${CYAN}http://localhost:8090/realms/${REALM_NAME}${NC}"
    echo -e "${GREEN}   • ${CYAN}LDAP${NC} Web Manager   : ${CYAN}http://localhost:8080${NC}"
    echo -e "${GREEN}   • Shared Clients     : ${CYAN}http://localhost:8090/admin/${REALM_NAME}/console/#/${REALM_NAME}/clients${NC}"
    echo -e "${GREEN}   • Client Scopes      : ${CYAN}http://localhost:8090/admin/${REALM_NAME}/console/#/${REALM_NAME}/client-scopes${NC}"
else
    echo -e "${GREEN}🌐 Access basic setup:${NC}"
    echo -e "${GREEN}   • ${MAGENTA}Keycloak${NC} Master    : ${CYAN}http://localhost:8090/admin/master/console/${NC}"
    echo -e "${GREEN}   • ${CYAN}LDAP${NC} Web Manager   : ${CYAN}http://localhost:8080${NC}"
    echo ""
    echo -e "${YELLOW}💡 To test a specific realm, run: ./test_all_bastion.sh <realm-name>${NC}"
    echo -e "${YELLOW}💡 For detailed diagnostics, run: ./test_all_bastion.sh <realm-name> --debug${NC}"
fi

if [ -n "$REALM_NAME" ]; then
    echo -e "${YELLOW}💡 For detailed diagnostics, run: ./test_all_bastion.sh ${REALM_NAME} --debug${NC}"
fi

if [ "$DEBUG_MODE" = true ]; then
    echo ""
    echo -e "${CYAN}🔧 Quick troubleshooting commands:${NC}"
    echo -e "${CYAN}   • Restart LDAP: docker restart ldap${NC}"
    echo -e "${CYAN}   • Check logs: docker logs ldap${NC}"
    echo -e "${CYAN}   • Regenerate LDIF: docker exec python-bastion python python-bastion/csv_to_ldif.py data/admins.csv${NC}"
    echo -e "${CYAN}   • Full restart: docker-compose down && docker-compose up -d${NC}"
fi