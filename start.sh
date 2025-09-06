#!/bin/sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
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
echo "\nService URLs:"
echo "  ${CYAN}LDAP${NC}                        : ${BLUE}$LDAP_URL${NC}"
echo "  ${WHITE}LDAP manager${NC}                : ${BLUE}$WEBUI_URL${NC}"
echo "  ${MAGENTA}Keycloak${NC}                    : ${BLUE}$KEYCLOAK_URL${NC}"
echo ""
echo "Credentials:"
echo "  ${CYAN}LDAP${NC} Admin DN.              : ${YELLOW}cn=admin,dc=mycompany,dc=local${NC}"
echo "  ${WHITE}LDAP manager${NC} admin password : ${YELLOW}admin${NC}"
echo "  ${MAGENTA}Keycloak${NC} Admin username     : ${YELLOW}admin${NC}"
echo "  ${MAGENTA}Keycloak${NC} Admin password     : ${YELLOW}admin${NC}"
