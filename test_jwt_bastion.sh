#!/bin/bash

# JWT Role Verification Script for LDAP-Keycloak POC
# 
# This script runs inside the python-bastion container where all tools (jq, curl, etc.) are available
# This eliminates cross-platform compatibility issues with Windows/Git Bash

# If already running inside container, execute directly
if [ -f /.dockerenv ]; then
    exec ./test_jwt.sh "$@"
fi
# 
# This script tests JWT tokens and role assignments for users in a Keycloak realm
# that is integrated with LDAP user federation.
# Usage: ./test_jwt_bastion.sh <realm-name>
# Examples:
#   ./test_jwt_bastion.sh capgemini
#   ./test_jwt_bastion.sh walmart
#   ./test_jwt_bastion.sh mycompany

echo "========================================="
echo "JWT ROLE VERIFICATION"
echo "========================================="

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Check if python-bastion container is running
if ! docker ps --format '{{.Names}}' | grep -q '^python-bastion$'; then
    echo -e "${RED}❌ python-bastion container not running. Please start services first:${NC}"
    echo -e "${YELLOW}   ./start_all_bastion.sh <realm-name> --defaults${NC}"
    exit 1
fi

echo -e "${BLUE}🐳 Running JWT tests inside python-bastion container for cross-platform compatibility...${NC}"
echo ""

# Execute test_jwt.sh inside the container with all arguments passed through
docker exec -it python-bastion bash -c "cd /workspace && ./test_jwt.sh $*"

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ JWT tests completed successfully${NC}"
else
    echo ""
    echo -e "${RED}❌ JWT tests failed with exit code: ${EXIT_CODE}${NC}"
fi

exit $EXIT_CODE

