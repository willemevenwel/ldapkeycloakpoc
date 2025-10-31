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

# Keycloak Details and Status Script
# This script provides debugging information about the current Keycloak instance

KEYCLOAK_URL="$(get_keycloak_url)"
MASTER_ADMIN_USER="admin"
MASTER_ADMIN_PASSWORD="admin"

echo -e "${CYAN}🔍 Keycloak Instance Details${NC}"
echo -e "${CYAN}============================${NC}"

# Function to wait for Keycloak to be ready
wait_for_keycloak() {
    echo -e "${YELLOW}⏳ Checking if ${MAGENTA}Keycloak${NC} is accessible...${NC}"
    
    local max_attempts=10
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s -f "${KEYCLOAK_URL}/realms/master" > /dev/null 2>&1; then
            echo -e "${GREEN}✅ ${MAGENTA}Keycloak${NC} is accessible!${NC}"
            return 0
        else
            if [ $attempt -eq $max_attempts ]; then
                echo -e "${RED}❌ ${MAGENTA}Keycloak${NC} is not accessible after ${max_attempts} attempts${NC}"
                echo -e "${YELLOW}💡 Make sure Keycloak container is running: docker ps${NC}"
                return 1
            fi
            echo -e "${YELLOW}   Attempt ${attempt}/${max_attempts} - waiting...${NC}"
            sleep 2
            attempt=$((attempt + 1))
        fi
    done
}

# Function to get master admin token
get_master_admin_token() {
    echo -e "${YELLOW}🔑 Getting master admin token...${NC}"
    
    TOKEN_RESPONSE=$(curl -s -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=${MASTER_ADMIN_USER}" \
        -d "password=${MASTER_ADMIN_PASSWORD}" \
        -d "grant_type=password" \
        -d "client_id=admin-cli" 2>/dev/null)
    
    MASTER_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token' 2>/dev/null)
    
    if [ "$MASTER_TOKEN" = "null" ] || [ -z "$MASTER_TOKEN" ]; then
        echo -e "${RED}❌ Failed to get master admin token${NC}"
        echo -e "${YELLOW}💡 Check if master admin credentials are correct (admin/admin)${NC}"
        if command -v jq >/dev/null 2>&1; then
            echo -e "${RED}Response: $TOKEN_RESPONSE${NC}"
        else
            echo -e "${YELLOW}⚠️  jq not available - cannot parse token response${NC}"
        fi
        return 1
    fi
    
    echo -e "${GREEN}✅ Successfully obtained master admin token${NC}"
    return 0
}

# Function to get Keycloak server info
get_keycloak_version() {
    echo -e "${YELLOW}🏷️  Getting ${MAGENTA}Keycloak${NC} server information...${NC}"
    
    if [ -z "$MASTER_TOKEN" ]; then
        echo -e "${RED}❌ No master token available${NC}"
        return 1
    fi
    
    SERVER_INFO=$(curl -s -X GET "${KEYCLOAK_URL}/admin/serverinfo" \
        -H "Authorization: Bearer ${MASTER_TOKEN}" \
        -H "Content-Type: application/json" 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$SERVER_INFO" ]; then
        echo -e "${RED}❌ Failed to get server information${NC}"
        return 1
    fi
    
    if command -v jq >/dev/null 2>&1; then
        KEYCLOAK_VERSION=$(echo "$SERVER_INFO" | jq -r '.systemInfo.version // "Unknown"' 2>/dev/null)
        KEYCLOAK_BUILD=$(echo "$SERVER_INFO" | jq -r '.systemInfo.serverTime // "Unknown"' 2>/dev/null)
        
        echo -e "${GREEN}📊 Server Information:${NC}"
        echo -e "   • Version: ${BLUE}${KEYCLOAK_VERSION}${NC}"
        echo -e "   • Server Time: ${BLUE}${KEYCLOAK_BUILD}${NC}"
        
        # Get Java information
        JAVA_VERSION=$(echo "$SERVER_INFO" | jq -r '.systemInfo.javaVersion // "Unknown"' 2>/dev/null)
        JAVA_VENDOR=$(echo "$SERVER_INFO" | jq -r '.systemInfo.javaVendor // "Unknown"' 2>/dev/null)
        echo -e "   • Java Version: ${BLUE}${JAVA_VERSION}${NC}"
        echo -e "   • Java Vendor: ${BLUE}${JAVA_VENDOR}${NC}"
        
        # Check for Organizations feature availability (Keycloak 25+)
        if [ "$KEYCLOAK_VERSION" != "Unknown" ]; then
            VERSION_MAJOR=$(echo "$KEYCLOAK_VERSION" | cut -d'.' -f1)
            if [ "$VERSION_MAJOR" -ge 25 ] 2>/dev/null; then
                echo -e "   • Organizations Feature: ${GREEN}Available (v25+)${NC}"
            else
                echo -e "   • Organizations Feature: ${YELLOW}Not Available (requires v25+)${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}⚠️  jq not available - showing raw server info${NC}"
        echo -e "${BLUE}Raw server info available but not parsed${NC}"
    fi
    
    return 0
}

# Function to list existing realms
list_existing_realms() {
    echo -e "${YELLOW}🏰 Listing existing realms...${NC}"
    
    if [ -z "$MASTER_TOKEN" ]; then
        echo -e "${RED}❌ No master token available${NC}"
        return 1
    fi
    
    REALMS_RESPONSE=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms" \
        -H "Authorization: Bearer ${MASTER_TOKEN}" \
        -H "Content-Type: application/json" 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$REALMS_RESPONSE" ]; then
        echo -e "${RED}❌ Failed to get realms list${NC}"
        return 1
    fi
    
    if command -v jq >/dev/null 2>&1; then
        REALM_NAMES=$(echo "$REALMS_RESPONSE" | jq -r '.[].realm' 2>/dev/null | sort)
        REALM_COUNT=$(echo "$REALMS_RESPONSE" | jq '. | length' 2>/dev/null)
        
        echo -e "${GREEN}📋 Found ${REALM_COUNT} realm(s):${NC}"
        
        if [ -n "$REALM_NAMES" ]; then
            while IFS= read -r realm; do
                if [ "$realm" = "master" ]; then
                    echo -e "   • ${CYAN}${realm}${NC} ${YELLOW}(system realm)${NC}"
                else
                    echo -e "   • ${BLUE}${realm}${NC}"
                fi
            done <<< "$REALM_NAMES"
        else
            echo -e "${YELLOW}   No realms found${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  jq not available - cannot parse realms list${NC}"
        echo -e "${BLUE}Raw realms data available but not parsed${NC}"
    fi
    
    return 0
}

# Function to check Docker container status
check_docker_status() {
    echo -e "${YELLOW}🐳 Checking Docker container status...${NC}"
    
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${RED}❌ Docker command not available${NC}"
        return 1
    fi
    
    # Check if Keycloak container is running
    KEYCLOAK_CONTAINER=$(docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep keycloak)
    
    if [ -n "$KEYCLOAK_CONTAINER" ]; then
        echo -e "${GREEN}✅ Keycloak container status:${NC}"
        echo -e "${BLUE}   $KEYCLOAK_CONTAINER${NC}"
    else
        echo -e "${RED}❌ Keycloak container not found or not running${NC}"
        echo -e "${YELLOW}💡 All containers:${NC}"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | head -5
        return 1
    fi
    
    return 0
}

# Function to display connection details
display_connection_info() {
    echo -e "${YELLOW}🌐 Connection Information:${NC}"
    echo -e "   • Keycloak URL: ${BLUE}${KEYCLOAK_URL}${NC}"
    echo -e "   • Master Admin: ${BLUE}${MASTER_ADMIN_USER}${NC}"
    echo -e "   • Admin Console: ${BLUE}${KEYCLOAK_URL}/admin/master/console/${NC}"
    echo ""
}

# Main execution
echo -e "${GREEN}🚀 Starting Keycloak details check...${NC}"
echo ""

# Check Docker status first
check_docker_status
echo ""

# Check Keycloak accessibility
if wait_for_keycloak; then
    echo ""
    
    # Get admin token
    if get_master_admin_token; then
        echo ""
        
        # Get server version and info
        get_keycloak_version
        echo ""
        
        # List existing realms
        list_existing_realms
        echo ""
        
        # Display connection info
        display_connection_info
        
        echo -e "${GREEN}✅ Keycloak details check completed successfully!${NC}"
    else
        echo -e "${RED}❌ Could not authenticate with Keycloak${NC}"
        echo ""
        display_connection_info
        exit 1
    fi
else
    echo -e "${RED}❌ Keycloak is not accessible${NC}"
    echo ""
    display_connection_info
    exit 1
fi

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"