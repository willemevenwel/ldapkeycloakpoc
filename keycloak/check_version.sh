#!/bin/bash

# Keycloak Version Checker Utility
# This script checks the Keycloak version and feature availability

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
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

KEYCLOAK_URL="$(get_keycloak_url)"

# Function to show help
show_help() {
    echo -e "${GREEN}Keycloak Version Checker${NC}"
    echo ""
    echo -e "${YELLOW}Usage:${NC}"
    echo -e "  $0 [options]"
    echo ""
    echo -e "${YELLOW}Description:${NC}"
    echo -e "  Checks Keycloak version and feature availability"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  -h, --help           Show this help message"
    echo -e "  --check-orgs         Check if Organizations feature is available"
    echo -e "  --min-version <ver>  Check if version meets minimum requirement"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo -e "  $0"
    echo -e "  $0 --check-orgs"
    echo -e "  $0 --min-version 25"
    echo ""
    exit 0
}

# Check for help flag
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
fi

# Function to get admin token
get_admin_token() {
    echo -e "${YELLOW}� Getting admin token...${NC}"
    
    # Try master admin first (most reliable)
    TOKEN_RESPONSE=$(curl -s -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=admin" \
        -d "password=admin" \
        -d "grant_type=password" \
        -d "client_id=admin-cli")
    
    TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
    
    if [ "$TOKEN" = "null" ] || [ -z "$TOKEN" ]; then
        echo -e "${RED}❌ Failed to get admin token${NC}"
        echo -e "${RED}Response: $TOKEN_RESPONSE${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✅ Got admin token${NC}"
}

# Function to get Keycloak version
get_keycloak_version() {
    echo -e "${YELLOW}🔍 Checking Keycloak version...${NC}"
    
    # Get admin token first
    get_admin_token || return 1
    
    # Get server info using admin token
    SERVER_INFO=$(curl -s -X GET "${KEYCLOAK_URL}/admin/serverinfo" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" 2>/dev/null)
    
    if [ -z "$SERVER_INFO" ]; then
        echo -e "${RED}❌ Cannot connect to Keycloak at ${KEYCLOAK_URL}${NC}"
        return 1
    fi
    
    # Extract version using jq
    if ! command -v jq >/dev/null 2>&1; then
        echo -e "${RED}❌ jq is not installed. Please install jq to use this tool.${NC}"
        return 1
    fi
    
    KEYCLOAK_VERSION=$(echo "$SERVER_INFO" | jq -r '.systemInfo.version // "Unknown"' 2>/dev/null)
    
    if [ "$KEYCLOAK_VERSION" = "Unknown" ] || [ -z "$KEYCLOAK_VERSION" ] || [ "$KEYCLOAK_VERSION" = "null" ]; then
        echo -e "${YELLOW}⚠️  Could not determine Keycloak version from server info${NC}"
        return 1
    fi
    
    VERSION_MAJOR=$(echo "$KEYCLOAK_VERSION" | cut -d'.' -f1)
    VERSION_MINOR=$(echo "$KEYCLOAK_VERSION" | cut -d'.' -f2)
    
    echo -e "${GREEN}✅ Keycloak Version: ${MAGENTA}${KEYCLOAK_VERSION}${NC}"
    echo -e "${BLUE}   Major: ${VERSION_MAJOR}, Minor: ${VERSION_MINOR}${NC}"
}

# Function to check Organizations feature availability
check_organizations_feature() {
    echo -e "${YELLOW}🔍 Checking Organizations feature availability...${NC}"
    
    if [ -z "$VERSION_MAJOR" ]; then
        echo -e "${YELLOW}⚠️  Cannot check Organizations feature (version unknown)${NC}"
        return 0
    fi
    
    # Organizations feature requires Keycloak 25+
    if [ "$VERSION_MAJOR" -lt 25 ] 2>/dev/null; then
        echo -e "${RED}❌ Organizations feature NOT available${NC}"
        echo -e "${YELLOW}   Requires: Keycloak 25.0 or higher${NC}"
        echo -e "${YELLOW}   Current: ${KEYCLOAK_VERSION}${NC}"
        return 1
    else
        echo -e "${GREEN}✅ Organizations feature should be available (Keycloak ${KEYCLOAK_VERSION} >= 25)${NC}"
        
        # Try to verify by testing the Organizations API endpoint
        echo -e "${YELLOW}🔍 Verifying Organizations API accessibility...${NC}"
        
        # Try to query a realm's organizations endpoint (using master realm as test)
        HTTP_STATUS=$(curl -s -w "%{http_code}" -X GET "${KEYCLOAK_URL}/admin/realms/master/organizations" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -o /tmp/org_api_check.json)
        
        if [ "$HTTP_STATUS" = "200" ]; then
            echo -e "${GREEN}✅ Organizations API is accessible${NC}"
            echo -e "${BLUE}   The Organizations feature is fully functional${NC}"
        else
            echo -e "${YELLOW}⚠️  Organizations API returned HTTP ${HTTP_STATUS}${NC}"
            echo -e "${YELLOW}   The feature may require realm-level enablement${NC}"
            if [ -f /tmp/org_api_check.json ]; then
                ERROR_MSG=$(cat /tmp/org_api_check.json | jq -r '.error // .errorMessage // empty' 2>/dev/null)
                if [ -n "$ERROR_MSG" ]; then
                    echo -e "${YELLOW}   Error: ${ERROR_MSG}${NC}"
                fi
            fi
        fi
        
        return 0
    fi
}

# Function to check minimum version requirement
check_min_version() {
    local min_version=$1
    echo -e "${YELLOW}🔍 Checking minimum version requirement...${NC}"
    
    if [ -z "$VERSION_MAJOR" ]; then
        echo -e "${YELLOW}⚠️  Cannot check version requirement (version unknown)${NC}"
        return 0
    fi
    
    if [ "$VERSION_MAJOR" -lt "$min_version" ] 2>/dev/null; then
        echo -e "${RED}❌ Version requirement NOT met${NC}"
        echo -e "${YELLOW}   Required: ${min_version}.0 or higher${NC}"
        echo -e "${YELLOW}   Current: ${KEYCLOAK_VERSION}${NC}"
        return 1
    else
        echo -e "${GREEN}✅ Version requirement met${NC}"
        echo -e "${BLUE}   Required: ${min_version}.0${NC}"
        echo -e "${BLUE}   Current: ${KEYCLOAK_VERSION}${NC}"
        return 0
    fi
}

# Function to display feature matrix
show_feature_matrix() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Feature Availability Matrix${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if [ -z "$VERSION_MAJOR" ]; then
        echo -e "${YELLOW}⚠️  Cannot determine feature availability (version unknown)${NC}"
        return 0
    fi
    
    # LDAP Integration (all versions)
    echo -e "${GREEN}✅ LDAP Integration${NC} - Available in all versions"
    
    # Role Mappers (all versions)
    echo -e "${GREEN}✅ Role Mappers${NC} - Available in all versions"
    
    # Client Scopes (all versions)
    echo -e "${GREEN}✅ Client Scopes${NC} - Available in all versions"
    
    # Organizations (25+)
    if [ "$VERSION_MAJOR" -ge 25 ] 2>/dev/null; then
        echo -e "${GREEN}✅ Organizations${NC} - Available (KC 25+)"
    else
        echo -e "${RED}❌ Organizations${NC} - Requires Keycloak 25+"
    fi
    
    # Fine-Grained Authorization (12+)
    if [ "$VERSION_MAJOR" -ge 12 ] 2>/dev/null; then
        echo -e "${GREEN}✅ Fine-Grained Authorization${NC} - Available (KC 12+)"
    else
        echo -e "${RED}❌ Fine-Grained Authorization${NC} - Requires Keycloak 12+"
    fi
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Main execution
echo -e "${GREEN}🔧 Keycloak Version Check${NC}"
echo ""

get_keycloak_version

# Parse options
CHECK_ORGS=false
MIN_VERSION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --check-orgs)
            CHECK_ORGS=true
            shift
            ;;
        --min-version)
            MIN_VERSION="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

if [ "$CHECK_ORGS" = true ]; then
    echo ""
    check_organizations_feature
fi

if [ -n "$MIN_VERSION" ]; then
    echo ""
    check_min_version "$MIN_VERSION"
fi

# Always show feature matrix
show_feature_matrix

echo ""
echo -e "${GREEN}✅ Version check complete${NC}"
