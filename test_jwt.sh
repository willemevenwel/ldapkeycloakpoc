#!/bin/bash

# JWT Role Verification Script for LDAP-Keycloak POC
# 
# This script runs inside the python-bastion container where all tools (jq, curl, etc.) are available
# This eliminates cross-platform compatibility issues with Windows/Git Bash

# Check if we're running inside the container or from host
if [ -f /.dockerenv ] || [ "$CONTAINER_RUNTIME" = "true" ]; then
    # We're inside the container - run the internal version
    exec ./test_jwt_internal.sh "$@"
else
    # We're on the host - execute inside python-bastion container
    echo "🐳 Running JWT tests inside python-bastion container for cross-platform compatibility..."
    
    # Check if python-bastion container is running
    if ! docker ps --format "table {{.Names}}" | grep -q "python-bastion"; then
        echo "❌ python-bastion container not running. Please start services first:"
        echo "   ./start_all_bastion.sh"
        exit 1
    fi
    
    # Execute the internal script inside the container
    docker exec -it python-bastion bash -c "cd /workspace && ./test_jwt_internal.sh $*"
fi
# 
# This script tests JWT tokens and role assignments for users in a Keycloak realm
# that is integrated with LDAP user federation.
# Usage: ./test_jwt.sh <realm-name>
# 
#   ./test_jwt.sh capgemini
#   ./test_jwt.sh walmart
#   ./test_jwt.sh mycompany

echo "========================================="
echo "JWT ROLE VERIFICATION"
echo "========================================="

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Function to get Python command (compatible with different environments)
get_python_cmd() {
    if command -v python3 >/dev/null 2>&1; then
        echo "python3"
    elif command -v python >/dev/null 2>&1; then
        echo "python"
    else
        echo "none"
    fi
}

# Function to get user password - tries CSV first, then username fallback
get_user_password() {
    local username=$1
    
    if [ -f "data/users.csv" ]; then
        # Look up password in CSV file
        local csv_password=$(grep "^${username}," data/users.csv | cut -d',' -f5 | tr -d '"' | tr -d ' ')
        if [ -n "$csv_password" ]; then
            echo "$csv_password"
            return
        fi
    fi
    
    # Fallback to username as password
    echo "$username"
}

# Function to try authentication with both CSV and fallback passwords
try_authenticate() {
    local username=$1
    local realm=$2
    local client_secret=$3
    
    # First try CSV password
    if [ -f "data/users.csv" ]; then
        local csv_password=$(grep "^${username}," data/users.csv | cut -d',' -f5 | tr -d '"' | tr -d ' ')
        if [ -n "$csv_password" ] && [ "$csv_password" != "$username" ]; then
            echo -e "🔍 Trying CSV password for $username ($csv_password)" >&2
            local token_response=$(curl -s -X POST "http://localhost:8090/realms/${realm}/protocol/openid-connect/token" \
                -H "Content-Type: application/x-www-form-urlencoded" \
                -d "grant_type=password" \
                -d "client_id=shared-web-client" \
                -d "client_secret=${client_secret}" \
                -d "username=${username}" \
                -d "password=${csv_password}")
            
            # Check if response contains access_token (compatible with Windows/Git Bash)
            PYTHON_CMD=$(get_python_cmd)
            if [ "$PYTHON_CMD" != "none" ] && echo "$token_response" | $PYTHON_CMD -c "import sys, json; data = json.load(sys.stdin); exit(0 if 'access_token' in data else 1)" 2>/dev/null; then
                echo "$token_response"
                return 0
            elif echo "$token_response" | grep -q '"access_token"'; then
                # Fallback if Python fails
                echo "$token_response"
                return 0
            fi
        fi
    fi
    
    # Fallback to username as password
    echo -e "🔍 Trying username password for $username ($username)" >&2
    local token_response=$(curl -s -X POST "http://localhost:8090/realms/${realm}/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=password" \
        -d "client_id=shared-web-client" \
        -d "client_secret=${client_secret}" \
        -d "username=${username}" \
        -d "password=${username}")
    
    echo "$token_response"
}

# Parse arguments
DEFAULTS_MODE=false

# Check for --defaults flag (can be first or last argument)
if [ "$1" = "--defaults" ]; then
    DEFAULTS_MODE=true
    REALM_NAME="capgemini"
    USERS=("test-acme-admin" "test-xyz-user" "test-multi-org")
    echo -e "${BLUE}🎯 Using defaults: realm=${REALM_NAME}, users=[${USERS[*]}]${NC}"
elif [ "$#" -ge 2 ] && [ "${!#}" = "--defaults" ]; then
    # --defaults is the last argument
    DEFAULTS_MODE=true
    REALM_NAME="$1"
    # TODO: Normalize realm name to lowercase for consistency (disabled for existing realm)
    # REALM_NAME=$(echo "$REALM_NAME" | tr '[:upper:]' '[:lower:]')
    USERS=("test-acme-admin" "test-xyz-user" "test-multi-org")
    echo -e "${BLUE}🎯 Using defaults: realm=${REALM_NAME}, users=[${USERS[*]}]${NC}"
elif [ $# -lt 2 ]; then
    echo -e "${RED}❌ Error: Insufficient arguments${NC}"
    echo ""
    echo -e "${YELLOW}Usage:${NC}"
    echo -e "${YELLOW}  $0 --defaults                           # Use capgemini realm with test-acme-admin, test-xyz-user, test-multi-org${NC}"
    echo -e "${YELLOW}  $0 <realm-name> --defaults              # Custom realm with default users${NC}"
    echo -e "${YELLOW}  $0 <realm-name> <user1> [user2] [...]   # Custom realm and users${NC}"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo -e "${YELLOW}  $0 --defaults${NC}"
    echo -e "${YELLOW}  $0 capgemini --defaults${NC}"
    echo -e "${YELLOW}  $0 capgemini test-acme-admin test-xyz-user${NC}"
    echo -e "${YELLOW}  $0 capgemini alice bob charlie${NC}"
    echo -e "${YELLOW}  $0 walmart alice bob charlie${NC}"
    echo -e "${YELLOW}  $0 mycompany john${NC}"
    exit 1
else
    REALM_NAME="$1"
    # TODO: Normalize realm name to lowercase for consistency (disabled for existing realm)
    # REALM_NAME=$(echo "$REALM_NAME" | tr '[:upper:]' '[:lower:]')
    shift  # Remove first argument (realm name)
    USERS=("$@")  # Remaining arguments are users
    echo -e "${BLUE}🏰 Using realm: ${REALM_NAME}${NC}"
    echo -e "${BLUE}👥 Testing users: [${USERS[*]}]${NC}"
fi

# User credentials will be looked up dynamically from CSV

# Get the current client secret dynamically
echo "🔑 Getting current client secret..."

# Get admin token for the specified realm
ADMIN_TOKEN=$(curl -s -X POST "http://localhost:8090/realms/${REALM_NAME}/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin-${REALM_NAME}" \
  -d "password=admin-${REALM_NAME}" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" 2>/dev/null | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)

if [ -z "$ADMIN_TOKEN" ]; then
    echo "❌ Failed to get admin token. Is Keycloak running with ${REALM_NAME} realm?"
    exit 1
fi

# Get shared-web-client UUID
CLIENT_UUID=$(curl -s -X GET "http://localhost:8090/admin/realms/${REALM_NAME}/clients?clientId=shared-web-client" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" 2>/dev/null | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -z "$CLIENT_UUID" ]; then
    echo "❌ Failed to find shared-web-client"
    exit 1
fi

# Get client secret
CLIENT_SECRET=$(curl -s -X GET "http://localhost:8090/admin/realms/${REALM_NAME}/clients/${CLIENT_UUID}/client-secret" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" 2>/dev/null | grep -o '"value":"[^"]*"' | cut -d'"' -f4)

if [ -z "$CLIENT_SECRET" ]; then
    echo "❌ Failed to get client secret"
    exit 1
fi

echo "✅ Client secret obtained successfully"
echo "🔍 Using client secret: ${CLIENT_SECRET:0:10}..." # Show first 10 chars for verification

echo ""
echo -e "${BLUE}=== CSV EXPECTATIONS (dynamically read from data/users.csv) ===${NC}"
if [[ -f "data/users.csv" ]]; then
    echo -e "${BLUE}Expected roles based on CSV group assignments:${NC}"
    while IFS=',' read -r username firstname lastname email password groups || [[ -n "$username" ]]; do
        # Skip header line
        [[ "$username" == "username" ]] && continue
        [[ -z "$username" ]] && continue
        
        # Replace semicolons with commas for display
        display_groups=$(echo "$groups" | sed 's/;/, /g')
        printf "  %-10s → %s\n" "$username" "$display_groups"
    done < "data/users.csv"
else
    echo -e "${RED}⚠️  data/users.csv not found - cannot show expected roles${NC}"
fi
echo ""
echo -e "${BLUE}💡 CSV Support: Script automatically reads passwords from data/users.csv${NC}"
echo ""

# Test each user dynamically
for USERNAME in "${USERS[@]}"; do
    USERNAME_UPPER=$(echo "$USERNAME" | tr '[:lower:]' '[:upper:]')
    echo -e "${YELLOW}=== ${USERNAME_UPPER}'S JWT TOKEN ===${NC}"
    
    # Try authentication with both CSV and fallback passwords
    TOKEN_RESPONSE=$(try_authenticate "$USERNAME" "$REALM_NAME" "$CLIENT_SECRET")
    
    # Extract access token (compatible with Windows/Git Bash)
    PYTHON_CMD=$(get_python_cmd)
    if [ "$PYTHON_CMD" != "none" ]; then
        ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | $PYTHON_CMD -c "import sys, json; print(json.load(sys.stdin)['access_token'])" 2>/dev/null)
    else
        ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')
    fi

    if [ "$ACCESS_TOKEN" = "null" ] || [ -z "$ACCESS_TOKEN" ]; then
        echo "❌ Failed to get access token for ${USERNAME}"
        echo "🔍 Error response: $TOKEN_RESPONSE"
        echo ""
        continue
    fi

    # Decode JWT token with proper padding
    JWT_PAYLOAD=$(echo "$ACCESS_TOKEN" | cut -d'.' -f2)
    # Add padding if needed for base64 decoding
    while [ $((${#JWT_PAYLOAD} % 4)) -ne 0 ]; do
        JWT_PAYLOAD="${JWT_PAYLOAD}="
    done
    
    TOKEN_FILE="/tmp/${USERNAME}_token.json"
    echo "$JWT_PAYLOAD" | base64 -d > "$TOKEN_FILE" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "✅ Token obtained and decoded"
    else
        echo "❌ Failed to decode JWT token for ${USERNAME}"
        echo ""
        continue
    fi

    echo ""
    echo "realm_access.roles (first 5):"
    # Extract realm roles (compatible with Windows/Git Bash)
    PYTHON_CMD=$(get_python_cmd)
    if [ "$PYTHON_CMD" != "none" ]; then
        $PYTHON_CMD -c "
import sys, json
try:
    with open('$TOKEN_FILE', 'r') as f:
        data = json.load(f)
    for role in data.get('realm_access', {}).get('roles', [])[:5]:
        print('  ' + role)
except:
    print('  (Unable to parse roles)')
" 2>/dev/null
    else
        echo "  (Python not available)"
    fi

    echo ""
    echo "acme_enabled:"
    # Extract acme_enabled flag (compatible with Windows/Git Bash)
    PYTHON_CMD=$(get_python_cmd)
    if [ "$PYTHON_CMD" != "none" ]; then
        $PYTHON_CMD -c "
import sys, json
try:
    with open('$TOKEN_FILE', 'r') as f:
        data = json.load(f)
    print('  ' + str(data.get('acme_enabled', 'null')))
except:
    print('  (Unable to parse)')
" 2>/dev/null
    else
        echo "  (Python not available)"
    fi

    echo ""
    echo "xyz_enabled:"
    # Extract xyz_enabled flag (compatible with Windows/Git Bash)
    PYTHON_CMD=$(get_python_cmd)
    if [ "$PYTHON_CMD" != "none" ]; then
        $PYTHON_CMD -c "
import sys, json
try:
    with open('$TOKEN_FILE', 'r') as f:
        data = json.load(f)
    print('  ' + str(data.get('xyz_enabled', 'null')))
except:
    print('  (Unable to parse)')
" 2>/dev/null
    else
        echo "  (Python not available)"
    fi

    echo ""
    echo "organization_enabled:"
    # Extract organization_enabled flag (compatible with Windows/Git Bash)
    PYTHON_CMD=$(get_python_cmd)
    if [ "$PYTHON_CMD" != "none" ]; then
        $PYTHON_CMD -c "
import sys, json
try:
    with open('$TOKEN_FILE', 'r') as f:
        data = json.load(f)
    print('  ' + str(data.get('organization_enabled', 'null')))
except:
    print('  (Unable to parse)')
" 2>/dev/null
    else
        echo "  (Python not available)"
    fi

    echo ""
done

echo -e "${GREEN}=== VERIFICATION COMPLETE ===${NC}"

# Cleanup
for USERNAME in "${USERS[@]}"; do
    rm -f "/tmp/${USERNAME}_token.json"
done