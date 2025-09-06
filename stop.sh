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


echo "${RED}Stopping all services and removing containers (keeping images and volumes)...${NC}"
docker-compose down --remove-orphans

echo "${GREEN}All services have been stopped and containers removed.${NC}"
echo "${YELLOW}${CYAN}LDAP${NC} server is now offline.${NC}"
