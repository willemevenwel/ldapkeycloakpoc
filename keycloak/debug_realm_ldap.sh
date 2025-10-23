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

# Get script directory for relative imports
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source network detection utility
if [ -f "${SCRIPT_DIR}/../network_detect.sh" ]; then
    source "${SCRIPT_DIR}/../network_detect.sh"
else
    echo -e "${RED}❌ Network detection utility not found${NC}"
    exit 1
fi

# Simple debug script to check realm and LDAP provider status

if [ $# -eq 0 ]; then
    echo "Usage: $0 <realm-name>"
    echo "Example: $0 circus"
    exit 1
fi

REALM="$1"
ADMIN_USERNAME="admin-${REALM}"
ADMIN_PASSWORD="${ADMIN_USERNAME}"
KEYCLOAK_URL="$(get_keycloak_url)"

echo "🔍 Checking realm: ${REALM}"

# Get token
TOKEN=$(curl -s -X POST "${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=${ADMIN_USERNAME}" \
    -d "password=${ADMIN_PASSWORD}" \
    -d "grant_type=password" \
    -d "client_id=admin-cli" | jq -r '.access_token')

if [ "$TOKEN" = "null" ] || [ -z "$TOKEN" ]; then
    echo "❌ Realm ${REALM} does not exist or admin user not accessible"
    exit 1
fi

echo "✅ Realm ${REALM} exists and is accessible"

# Get realm ID
REALM_ID=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" | jq -r '.id')

# Check for LDAP providers using realm ID
LDAP_PROVIDERS=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/components?parent=${REALM_ID}&type=org.keycloak.storage.UserStorageProvider" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json")

LDAP_COUNT=$(echo "$LDAP_PROVIDERS" | jq '. | length')

if [ "$LDAP_COUNT" -eq 0 ]; then
    echo "❌ No ${CYAN}LDAP${NC} providers found in realm ${REALM}"
else
    echo "✅ Found ${LDAP_COUNT} ${CYAN}LDAP${NC} provider(s) in realm ${REALM}:"
    echo "$LDAP_PROVIDERS" | jq '.[] | {id: .id, name: .name, enabled: .config.enabled[0]}'
fi
