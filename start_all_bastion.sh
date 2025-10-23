#!/bin/bash

# start_all_bastion.sh - Cross-platform LDAP-Keycloak POC Setup
# This script eliminates host platform issues by executing all operations 
# from within the python-bastion container

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Help function
show_help() {
    echo -e "${GREEN}LDAP-Keycloak POC Setup Script (Container-based)${NC}"
    echo -e "${CYAN}Eliminates Windows/WSL/Git Bash compatibility issues by running from python-bastion container${NC}"
    echo ""
    echo -e "${YELLOW}Usage: $0 [realm-name] [options]${NC}"
    echo ""
    echo -e "${CYAN}Options:${NC}"
    echo -e "  --defaults         Use default values for all prompts (fully automated)"
    echo -e "  --check-steps      Interactive mode with step-by-step confirmations"
    echo -e "  --sync-only        Only sync LDAP data (assumes realm already exists)"
    echo -e "  --load-users       Only load additional users into LDAP"
    echo -e "  --help, -h         Show this help message"
    echo ""
    echo -e "${CYAN}Examples:${NC}"
    echo -e "  $0 myrealm                         # Create 'myrealm' with prompts"
    echo -e "  $0 myrealm --defaults              # Create 'myrealm' with all defaults"
    echo -e "  $0 --defaults                      # Use default realm name and all defaults"
    echo -e "  $0 myrealm --check-steps           # Interactive mode with confirmations"
    echo -e "  $0 myrealm --sync-only             # Only sync LDAP (realm must exist)"
    echo -e "  $0 myrealm --load-users            # Only load additional users"
    echo ""
    echo -e "${CYAN}Default Values (when using --defaults):${NC}"
    echo -e "  • Realm name: myrealm"
    echo -e "  • Organizations: Yes (acme xyz)"
    echo -e "  • Load additional users: Yes"
    echo ""
    echo -e "${YELLOW}Benefits of Container-based Execution:${NC}"
    echo -e "  ✅ Eliminates Windows/WSL path translation issues"
    echo -e "  ✅ Consistent bash environment across all platforms"
    echo -e "  ✅ No Git Bash compatibility problems"
    echo -e "  ✅ Pre-installed tools (docker, curl, jq, ldap-utils)"
    echo -e "  ✅ Consistent file permissions and line endings"
    echo ""
    echo -e "${YELLOW}Troubleshooting:${NC}"
    echo -e "  If tools are missing: ${CYAN}docker-compose build utils${NC}"
}

# Check for help flag first
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    show_help
    exit 0
fi

echo -e "${GREEN}🐳 LDAP-Keycloak POC Setup (Container-based)${NC}"
echo -e "${CYAN}🚀 Eliminating host platform issues by running from python-bastion container${NC}"
echo ""

# Check if Docker is available on host
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker is not available on the host system${NC}"
    echo -e "${YELLOW}Please install Docker and try again${NC}"
    exit 1
fi

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo -e "${RED}❌ Docker Compose is not available on the host system${NC}"
    echo -e "${YELLOW}Please install Docker Compose and try again${NC}"
    exit 1
fi

# Parse arguments to determine mode
SYNC_ONLY=false
LOAD_USERS_ONLY=false
ORIGINAL_ARGS="$@"

# Check for special modes
for arg in "$@"; do
    case $arg in
        --sync-only)
            SYNC_ONLY=true
            ;;
        --load-users)
            LOAD_USERS_ONLY=true
            ;;
    esac
done

# Step 1: Start services (unless in sync-only mode)
if [ "$SYNC_ONLY" = false ] && [ "$LOAD_USERS_ONLY" = false ]; then
    echo -e "${GREEN}🔄 Step 1: Starting all Docker services...${NC}"
    
    # Use docker-compose or docker compose based on availability
    if command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE_CMD="docker-compose"
    else
        DOCKER_COMPOSE_CMD="docker compose"
    fi
    
    echo -e "${CYAN}Using command: ${DOCKER_COMPOSE_CMD}${NC}"
    
    $DOCKER_COMPOSE_CMD up -d
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Failed to start Docker services${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Docker services started successfully${NC}"
    echo -e "${YELLOW}⏳ Waiting for containers to initialize...${NC}"
    
    # Wait for the python-bastion container to be ready
    echo -e "${CYAN}🔍 Waiting for python-bastion container to be ready...${NC}"
    for i in {1..30}; do
        if docker exec python-bastion echo "Container ready" >/dev/null 2>&1; then
            echo -e "${GREEN}✅ python-bastion container is ready${NC}"
            break
        else
            echo -e "${YELLOW}⏳ Waiting for python-bastion container... ($i/30)${NC}"
            if [ $i -eq 30 ]; then
                echo -e "${RED}❌ python-bastion container failed to become ready${NC}"
                echo -e "${YELLOW}Container status:${NC}"
                docker ps --filter "name=python-bastion"
                exit 1
            fi
            sleep 2
        fi
    done
fi

# Special mode: Load users only
if [ "$LOAD_USERS_ONLY" = true ]; then
    echo -e "${GREEN}🔄 Loading additional users into LDAP...${NC}"
    
    # Extract realm name from arguments (remove --load-users flag)
    REALM_ARGS=$(echo "$ORIGINAL_ARGS" | sed 's/--load-users//g')
    
    docker exec -it python-bastion bash -c "cd /workspace && ./ldap/load_additional_users.sh $REALM_ARGS"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Additional users loaded successfully${NC}"
        echo -e "${CYAN}💡 You may want to sync LDAP data: $0 [realm-name] --sync-only${NC}"
    else
        echo -e "${RED}❌ Failed to load additional users${NC}"
        exit 1
    fi
    exit 0
fi

# Special mode: Sync only
if [ "$SYNC_ONLY" = true ]; then
    echo -e "${GREEN}🔄 Syncing LDAP data with Keycloak...${NC}"
    
    # Extract realm name from arguments (remove --sync-only flag)
    REALM_ARGS=$(echo "$ORIGINAL_ARGS" | sed 's/--sync-only//g' | xargs)
    
    if [ -z "$REALM_ARGS" ]; then
        echo -e "${RED}❌ Realm name required for sync operation${NC}"
        echo -e "${YELLOW}Usage: $0 <realm-name> --sync-only${NC}"
        exit 1
    fi
    
    docker exec -it python-bastion bash -c "cd /workspace/keycloak && ./sync_ldap.sh $REALM_ARGS"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ LDAP sync completed successfully${NC}"
    else
        echo -e "${RED}❌ LDAP sync failed${NC}"
        exit 1
    fi
    exit 0
fi

# Step 2: Execute the full setup from within the python-bastion container
echo -e "${GREEN}🔄 Step 2: Executing setup from python-bastion container...${NC}"
echo -e "${CYAN}🐳 This eliminates Windows/WSL/Git Bash compatibility issues${NC}"
echo ""

# Check if python-bastion container is running
if ! docker ps --format "{{.Names}}" | grep -q "^python-bastion$"; then
    echo -e "${RED}❌ python-bastion container is not running${NC}"
    echo -e "${YELLOW}Please ensure Docker services are started first${NC}"
    exit 1
fi

# Execute the internal setup script within the container
echo -e "${CYAN}📋 Executing: docker exec -it python-bastion bash -c 'cd /workspace && ./start_all_bastion_internal.sh $ORIGINAL_ARGS'${NC}"
echo ""

docker exec -it python-bastion bash -c "cd /workspace && ./start_all_bastion_internal.sh $ORIGINAL_ARGS"

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}🎉 Container-based setup completed successfully!${NC}"
    echo ""
    echo -e "${CYAN}🌟 Advantages of this approach:${NC}"
    echo -e "${CYAN}   ✅ No Windows/WSL path translation issues${NC}"
    echo -e "${CYAN}   ✅ Consistent Linux environment across all host platforms${NC}"
    echo -e "${CYAN}   ✅ Reliable bash scripting without Git Bash quirks${NC}"
    echo -e "${CYAN}   ✅ All tools (curl, jq, ldap-utils) available and consistent${NC}"
    echo -e "${CYAN}   ✅ Proper file permissions and line ending handling${NC}"
    echo ""
    echo -e "${YELLOW}💡 You can now use this approach on any platform (Windows/macOS/Linux)${NC}"
    echo -e "${YELLOW}   without worrying about shell compatibility issues!${NC}"
else
    echo -e "${RED}❌ Container-based setup failed${NC}"
    echo -e "${YELLOW}Check the output above for error details${NC}"
    exit 1
fi