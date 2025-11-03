#!/bin/bash

# Container-Based Application JWT Test Wrapper
# Executes test_application_jwt.sh inside python-bastion container for cross-platform compatibility

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check if python-bastion container is running
if ! docker ps --format '{{.Names}}' | grep -q '^python-bastion$'; then
    echo -e "${RED}❌ python-bastion container not running. Please start services first:${NC}"
    echo -e "${YELLOW}   ./start_all_bastion.sh <realm-name> --defaults${NC}"
    exit 1
fi

echo -e "${CYAN}🐳 Running application JWT tests inside python-bastion container for cross-platform compatibility...${NC}"
echo ""

# Execute test_application_jwt.sh inside the container
docker exec -it python-bastion bash -c "cd /workspace && ./test_application_jwt.sh $*"

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ Application JWT tests completed successfully${NC}"
else
    echo ""
    echo -e "${RED}❌ Application JWT tests failed with exit code: ${EXIT_CODE}${NC}"
fi

exit $EXIT_CODE
