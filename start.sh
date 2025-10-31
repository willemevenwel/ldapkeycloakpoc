#!/bin/sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
BLACK='\033[0;30m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
NC='\033[0m' # No Color


mkdir -p ldif

echo "Building ${WHITE}ldap-manager${NC} Docker image..."
docker-compose build ldap-manager

docker-compose up -d

# Print service URLs
LDAP_URL="ldap://localhost:389"
WEBUI_URL="http://localhost:8080"
KEYCLOAK_URL="http://localhost:8090"
WEAVESCOPE_URL="http://localhost:4040"
DASHBOARD_URL="http://localhost:8888"
MOCK_OAUTH2_URL="http://localhost:8081"
echo "\LDAP Details:"
echo "  ${CYAN}LDAP${NC}                        : ${BLUE}$LDAP_URL${NC}"
echo "  ${CYAN}LDAP${NC} Web Manager${NC}            : ${BLUE}$WEBUI_URL${NC}"
echo "  ${CYAN}LDAP${NC} Server (protocol)      : ${YELLOW}cn=admin,dc=min,dc=io / admin${NC}"
echo "  ${CYAN}LDAP${NC} Web Manager (web UI)${NC}   : ${YELLOW}admin / admin${NC}"
echo ""
echo "Keycloak Details:"
echo "  ${MAGENTA}Keycloak${NC}                    : ${BLUE}$KEYCLOAK_URL${NC}"
echo "  ${MAGENTA}Keycloak${NC} Admin              : ${YELLOW}admin / admin${NC}"
echo ""
echo "Network Topology & Monitoring:"
echo "  ${GREEN}Weave Scope${NC}                 : ${BLUE}$WEAVESCOPE_URL${NC}"
echo "  ${GREEN}Container Discovery${NC}         : Real-time container and network visualization"
echo "  ${GREEN}Network Topology${NC}            : Interactive network maps and dependencies"
echo ""
echo "OAuth2 Testing & Integration:"
echo "  ${WHITE}Mock OAuth2 Server${NC}          : ${BLUE}$MOCK_OAUTH2_URL${NC}"
echo "  ${WHITE}OIDC Configuration${NC}          : ${BLUE}$MOCK_OAUTH2_URL/default/.well-known/openid_configuration${NC}"
echo "  ${WHITE}Token Endpoint${NC}              : Test OAuth flows without external dependencies"
echo ""
echo "🚀 ${WHITE}Centralized Dashboard:${NC}"
echo "  ${YELLOW}POC Dashboard${NC}               : ${BLUE}$DASHBOARD_URL${NC}"
echo "  ${YELLOW}All Services & Credentials${NC}  : Complete overview with security warnings"

