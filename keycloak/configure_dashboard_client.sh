#!/bin/bash

# Script to create a confidential client for the dashboard to query Keycloak Admin API
# This client uses client credentials grant to get an admin token
# 
# IMPORTANT: The dashboard client MUST be created in the master realm so it can
# authenticate and query ALL realms. This is required because the dashboard needs
# to list available realms before the user selects one.
#
# Usage: ./configure_dashboard_client.sh <realm-name>

set -e

# Function to show help
show_help() {
    echo "Keycloak Dashboard Client Configuration Script"
    echo ""
    echo "Usage:"
    echo "  $0 <realm-name>"
    echo ""
    echo "Description:"
    echo "  Creates a service account client for the dashboard to query Keycloak APIs"
    echo "  Client is created in the master realm for cross-realm queries"
    echo ""
    echo "Arguments:"
    echo "  realm-name    Name of the realm (used for permissions setup)"
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 walmart"
    echo "  $0 capgemini"
    echo ""
    echo "Prerequisites:"
    echo "  - Keycloak must be running"
    echo "  - Realm must exist"
    echo ""
    echo "What this creates:"
    echo "  - dashboard-admin-client in master realm"
    echo "  - Service account with query permissions"
    echo "  - Cross-realm access to specified realm"
    echo ""
    echo "Permissions Granted:"
    echo "  - view-realm, view-users, view-clients"
    echo "  - query-realms, query-users, query-clients"
    echo ""
    exit 0
}

# Check for help flag first
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
fi

# Check if realm name parameter is provided
if [ $# -eq 0 ]; then
    echo "❌ Error: Realm name is required"
    echo ""
    echo "Usage: $0 <realm-name>"
    echo "Try: $0 --help for more information"
    exit 1
fi

TARGET_REALM="$1"

# Get script directory for network detection
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source network detection utility
if [ -f "${SCRIPT_DIR}/../network_detect.sh" ]; then
    source "${SCRIPT_DIR}/../network_detect.sh"
    KEYCLOAK_URL="$(get_keycloak_url)"
else
    # Fallback if network_detect.sh not found
    KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8090}"
fi

# Dashboard client MUST be in master realm to query all realms
REALM_NAME="master"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS:-admin}"
AUTH_REALM="master"

echo "=========================================="
echo "Creating Dashboard Admin Client"
echo "Realm: $REALM_NAME (master realm required for cross-realm queries)"
echo "=========================================="

# Get admin token
echo "Authenticating as $ADMIN_USER in realm $AUTH_REALM..."
ADMIN_TOKEN=$(curl -s -X POST "$KEYCLOAK_URL/realms/${AUTH_REALM}/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=$ADMIN_USER" \
  -d "password=$ADMIN_PASS" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | jq -r '.access_token')

if [ -z "$ADMIN_TOKEN" ] || [ "$ADMIN_TOKEN" = "null" ]; then
    echo "Error: Failed to get admin token"
    exit 1
fi

echo "✓ Admin authenticated"

# Create the dashboard client
CLIENT_ID="dashboard-admin-client"
echo ""
echo "Creating client: $CLIENT_ID..."

CLIENT_JSON=$(cat <<EOF
{
  "clientId": "$CLIENT_ID",
  "name": "Dashboard Admin Client",
  "description": "Confidential client for dashboard to query Keycloak Admin API",
  "enabled": true,
  "clientAuthenticatorType": "client-secret",
  "publicClient": false,
  "serviceAccountsEnabled": true,
  "directAccessGrantsEnabled": false,
  "standardFlowEnabled": false,
  "protocol": "openid-connect"
}
EOF
)

# Check if client already exists
EXISTING_CLIENT=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/${REALM_NAME}/clients" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" | jq -r ".[] | select(.clientId==\"$CLIENT_ID\") | .id")

if [ -n "$EXISTING_CLIENT" ] && [ "$EXISTING_CLIENT" != "null" ]; then
    echo "Client already exists, updating..."
    curl -s -X PUT "$KEYCLOAK_URL/admin/realms/${REALM_NAME}/clients/$EXISTING_CLIENT" \
      -H "Authorization: Bearer $ADMIN_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$CLIENT_JSON"
    CLIENT_UUID="$EXISTING_CLIENT"
else
    echo "Creating new client..."
    curl -s -X POST "$KEYCLOAK_URL/admin/realms/${REALM_NAME}/clients" \
      -H "Authorization: Bearer $ADMIN_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$CLIENT_JSON"
    
    # Get the created client's UUID
    CLIENT_UUID=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/${REALM_NAME}/clients" \
      -H "Authorization: Bearer $ADMIN_TOKEN" \
      -H "Content-Type: application/json" | jq -r ".[] | select(.clientId==\"$CLIENT_ID\") | .id")
fi

echo "✓ Client created/updated"

# Generate a new secret for the client
echo ""
echo "Generating new client secret..."
curl -s -X POST "$KEYCLOAK_URL/admin/realms/${REALM_NAME}/clients/$CLIENT_UUID/client-secret" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" > /dev/null
echo "✓ New secret generated"

# Get the service account user
echo ""
echo "Getting service account user..."
SERVICE_ACCOUNT_USER=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/${REALM_NAME}/clients/$CLIENT_UUID/service-account-user" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" | jq -r '.id')

if [ -z "$SERVICE_ACCOUNT_USER" ] || [ "$SERVICE_ACCOUNT_USER" = "null" ]; then
    echo "Error: Could not get service account user"
    exit 1
fi

echo "✓ Service account user ID: $SERVICE_ACCOUNT_USER"

# Assign admin roles to the service account
echo ""
echo "Assigning admin roles to service account..."

# For master realm, we need to assign master realm admin roles
# These roles allow querying all realms
if [ "$REALM_NAME" = "master" ]; then
    # Get the master realm admin client roles
    MASTER_ADMIN_CLIENT=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/master/clients" \
      -H "Authorization: Bearer $ADMIN_TOKEN" \
      -H "Content-Type: application/json" | jq -r '.[] | select(.clientId=="master-realm") | .id')
    
    if [ -z "$MASTER_ADMIN_CLIENT" ] || [ "$MASTER_ADMIN_CLIENT" = "null" ]; then
        echo "⚠️  Warning: Could not find master-realm client"
        echo "    Dashboard client may not have sufficient permissions for cross-realm queries"
    else
        echo "✓ Found master-realm client: $MASTER_ADMIN_CLIENT"
        
        # Get available client roles from master-realm
        echo "  Getting available master-realm roles..."
        AVAILABLE_ROLES=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/master/users/$SERVICE_ACCOUNT_USER/role-mappings/clients/$MASTER_ADMIN_CLIENT/available" \
          -H "Authorization: Bearer $ADMIN_TOKEN" \
          -H "Content-Type: application/json")
        
        # For cross-realm access, we need these key roles
        ROLES_TO_ASSIGN=$(echo "$AVAILABLE_ROLES" | jq -c '[.[] | select(.name | IN("view-realm", "view-users", "view-clients", "query-realms", "query-clients", "query-users"))]')
        
        ROLE_COUNT=$(echo "$ROLES_TO_ASSIGN" | jq 'length')
        
        if [ "$ROLE_COUNT" -gt 0 ]; then
            # Assign the master-realm client roles
            curl -s -X POST "$KEYCLOAK_URL/admin/realms/master/users/$SERVICE_ACCOUNT_USER/role-mappings/clients/$MASTER_ADMIN_CLIENT" \
              -H "Authorization: Bearer $ADMIN_TOKEN" \
              -H "Content-Type: application/json" \
              -d "$ROLES_TO_ASSIGN"
            echo "✓ Assigned $ROLE_COUNT master-realm roles to service account"
            echo "  Roles: $(echo "$ROLES_TO_ASSIGN" | jq -r '[.[].name] | join(", ")')"
            echo "  ℹ️  These roles allow querying ALL realms in Keycloak"
        else
            echo "⚠️  Warning: No suitable master-realm roles found"
            echo "    The service account may already have all necessary roles"
        fi
    fi
else
    # For non-master realms, use realm-management client
    REALM_MGMT_CLIENT=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/${REALM_NAME}/clients" \
      -H "Authorization: Bearer $ADMIN_TOKEN" \
      -H "Content-Type: application/json" | jq -r '.[] | select(.clientId=="realm-management") | .id')
    
    if [ -z "$REALM_MGMT_CLIENT" ] || [ "$REALM_MGMT_CLIENT" = "null" ]; then
        echo "⚠️  Warning: Could not find realm-management client"
        echo "    Dashboard client may not have sufficient permissions for admin API"
    else
        echo "✓ Found realm-management client: $REALM_MGMT_CLIENT"
        
        # Get available client roles from realm-management
        echo "  Getting available realm-management roles..."
        AVAILABLE_ROLES=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/${REALM_NAME}/users/$SERVICE_ACCOUNT_USER/role-mappings/clients/$REALM_MGMT_CLIENT/available" \
          -H "Authorization: Bearer $ADMIN_TOKEN" \
          -H "Content-Type: application/json")
        
        # Extract key admin roles we need
        ROLES_TO_ASSIGN=$(echo "$AVAILABLE_ROLES" | jq -c '[.[] | select(.name | IN("view-realm", "view-users", "view-clients", "query-realms", "query-clients", "query-users", "manage-clients", "manage-users"))]')
        
        ROLE_COUNT=$(echo "$ROLES_TO_ASSIGN" | jq 'length')
        
        if [ "$ROLE_COUNT" -gt 0 ]; then
            # Assign the realm-management client roles
            curl -s -X POST "$KEYCLOAK_URL/admin/realms/${REALM_NAME}/users/$SERVICE_ACCOUNT_USER/role-mappings/clients/$REALM_MGMT_CLIENT" \
              -H "Authorization: Bearer $ADMIN_TOKEN" \
              -H "Content-Type: application/json" \
              -d "$ROLES_TO_ASSIGN"
            echo "✓ Assigned $ROLE_COUNT realm-management roles to service account"
            echo "  Roles: $(echo "$ROLES_TO_ASSIGN" | jq -r '[.[].name] | join(", ")')"
        else
            echo "⚠️  Warning: No suitable realm-management roles found"
            echo "    The service account may already have all necessary roles"
        fi
    fi
fi

# For master realm clients, also assign permissions to query other realms
if [ "$REALM_NAME" = "master" ]; then
    echo ""
    echo "🔍 Assigning permissions for non-master realms..."
    
    # Get list of all realms
    ALL_REALMS=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms" \
      -H "Authorization: Bearer $ADMIN_TOKEN" \
      -H "Content-Type: application/json" | jq -r '.[] | select(.realm != "master") | .realm')
    
    if [ -n "$ALL_REALMS" ]; then
        for OTHER_REALM in $ALL_REALMS; do
            echo "  📋 Configuring access to realm: $OTHER_REALM"
            
            # Get the {realm}-realm client for this specific realm
            REALM_CLIENT=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/master/clients" \
              -H "Authorization: Bearer $ADMIN_TOKEN" \
              -H "Content-Type: application/json" | jq -r ".[] | select(.clientId==\"${OTHER_REALM}-realm\") | .id")
            
            if [ -n "$REALM_CLIENT" ] && [ "$REALM_CLIENT" != "null" ]; then
                # Get available roles for this realm client
                REALM_AVAILABLE_ROLES=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/master/users/$SERVICE_ACCOUNT_USER/role-mappings/clients/$REALM_CLIENT/available" \
                  -H "Authorization: Bearer $ADMIN_TOKEN" \
                  -H "Content-Type: application/json")
                
                # Assign view/query roles for this realm
                REALM_ROLES=$(echo "$REALM_AVAILABLE_ROLES" | jq -c '[.[] | select(.name | IN("view-realm", "view-users", "view-clients", "query-realms", "query-clients", "query-users"))]')
                
                REALM_ROLE_COUNT=$(echo "$REALM_ROLES" | jq 'length')
                
                if [ "$REALM_ROLE_COUNT" -gt 0 ]; then
                    curl -s -X POST "$KEYCLOAK_URL/admin/realms/master/users/$SERVICE_ACCOUNT_USER/role-mappings/clients/$REALM_CLIENT" \
                      -H "Authorization: Bearer $ADMIN_TOKEN" \
                      -H "Content-Type: application/json" \
                      -d "$REALM_ROLES" > /dev/null
                    echo "     ✓ Assigned $REALM_ROLE_COUNT roles for realm: $OTHER_REALM"
                else
                    echo "     ⚠️  No roles available for realm: $OTHER_REALM (may already be assigned)"
                fi
            else
                echo "     ⚠️  Client ${OTHER_REALM}-realm not found"
            fi
        done
        echo "  ✅ Cross-realm permissions configured"
    else
        echo "  ℹ️  No other realms found (only master realm exists)"
    fi
fi

# Get the client secret
echo ""
echo "=========================================="
echo "Dashboard Client Configuration"
echo "Realm: $REALM_NAME"
echo "=========================================="
CLIENT_SECRET=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/${REALM_NAME}/clients/$CLIENT_UUID/client-secret" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" | jq -r '.value')

echo ""
echo "Client ID: $CLIENT_ID"
echo "Client Secret: $CLIENT_SECRET"
echo ""
echo "⚠️  IMPORTANT: Copy this client secret!"
echo "    You'll need to paste it into the token-viewer dashboard to enable API access."
echo ""
echo "Test the client with:"
echo "curl -X POST '$KEYCLOAK_URL/realms/${REALM_NAME}/protocol/openid-connect/token' \\"
echo "  -H 'Content-Type: application/x-www-form-urlencoded' \\"
echo "  -d 'grant_type=client_credentials' \\"
echo "  -d 'client_id=$CLIENT_ID' \\"
echo "  -d 'client_secret=$CLIENT_SECRET'"
echo ""
echo "=========================================="
echo "✓ Dashboard client setup complete!"
echo "=========================================="
