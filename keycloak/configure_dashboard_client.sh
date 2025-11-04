#!/bin/bash

# Script to create a confidential client for the dashboard to query Keycloak Admin API
# This client uses client credentials grant to get an admin token
# Usage: ./configure_dashboard_client.sh [realm-name]

set -e

KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8090}"
REALM_NAME="${1:-master}"

# Use realm-specific admin credentials if not master realm
if [ "$REALM_NAME" = "master" ]; then
    ADMIN_USER="${ADMIN_USER:-admin}"
    ADMIN_PASS="${ADMIN_PASS:-admin}"
    AUTH_REALM="master"
else
    ADMIN_USER="${ADMIN_USER:-admin-${REALM_NAME}}"
    ADMIN_PASS="${ADMIN_PASS:-admin-${REALM_NAME}}"
    AUTH_REALM="$REALM_NAME"
fi

echo "=========================================="
echo "Creating Dashboard Admin Client"
echo "Realm: $REALM_NAME"
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
  "secret": "dashboard-secret-change-in-production",
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

# Get realm admin roles - check for 'admin' role first
ADMIN_ROLE=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/${REALM_NAME}/roles" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" | jq -c '.[] | select(.name=="admin")')

if [ -n "$ADMIN_ROLE" ] && [ "$ADMIN_ROLE" != "null" ]; then
    # Assign admin role
    curl -s -X POST "$KEYCLOAK_URL/admin/realms/${REALM_NAME}/users/$SERVICE_ACCOUNT_USER/role-mappings/realm" \
      -H "Authorization: Bearer $ADMIN_TOKEN" \
      -H "Content-Type: application/json" \
      -d "[$ADMIN_ROLE]"
    echo "✓ Admin role assigned"
else
    echo "⚠️  Warning: Could not find admin role, assigning query/view roles instead..."
    
    # Fallback: assign query/view roles that exist in the realm
    QUERY_REALMS=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/${REALM_NAME}/roles" \
      -H "Authorization: Bearer $ADMIN_TOKEN" \
      -H "Content-Type: application/json" | jq -c '.[] | select(.name=="query-realms")')
    QUERY_CLIENTS=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/${REALM_NAME}/roles" \
      -H "Authorization: Bearer $ADMIN_TOKEN" \
      -H "Content-Type: application/json" | jq -c '.[] | select(.name=="query-clients")')
    QUERY_USERS=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/${REALM_NAME}/roles" \
      -H "Authorization: Bearer $ADMIN_TOKEN" \
      -H "Content-Type: application/json" | jq -c '.[] | select(.name=="query-users")')
    VIEW_USERS=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/${REALM_NAME}/roles" \
      -H "Authorization: Bearer $ADMIN_TOKEN" \
      -H "Content-Type: application/json" | jq -c '.[] | select(.name=="view-users")')
    VIEW_CLIENTS=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/${REALM_NAME}/roles" \
      -H "Authorization: Bearer $ADMIN_TOKEN" \
      -H "Content-Type: application/json" | jq -c '.[] | select(.name=="view-clients")')
    VIEW_REALM=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/${REALM_NAME}/roles" \
      -H "Authorization: Bearer $ADMIN_TOKEN" \
      -H "Content-Type: application/json" | jq -c '.[] | select(.name=="view-realm")')
    
    ROLES_JSON="["
    [ -n "$QUERY_REALMS" ] && [ "$QUERY_REALMS" != "null" ] && ROLES_JSON="${ROLES_JSON}${QUERY_REALMS},"
    [ -n "$QUERY_CLIENTS" ] && [ "$QUERY_CLIENTS" != "null" ] && ROLES_JSON="${ROLES_JSON}${QUERY_CLIENTS},"
    [ -n "$QUERY_USERS" ] && [ "$QUERY_USERS" != "null" ] && ROLES_JSON="${ROLES_JSON}${QUERY_USERS},"
    [ -n "$VIEW_USERS" ] && [ "$VIEW_USERS" != "null" ] && ROLES_JSON="${ROLES_JSON}${VIEW_USERS},"
    [ -n "$VIEW_CLIENTS" ] && [ "$VIEW_CLIENTS" != "null" ] && ROLES_JSON="${ROLES_JSON}${VIEW_CLIENTS},"
    [ -n "$VIEW_REALM" ] && [ "$VIEW_REALM" != "null" ] && ROLES_JSON="${ROLES_JSON}${VIEW_REALM},"
    ROLES_JSON="${ROLES_JSON%,}]"
    
    if [ "$ROLES_JSON" != "[]" ]; then
        curl -s -X POST "$KEYCLOAK_URL/admin/realms/${REALM_NAME}/users/$SERVICE_ACCOUNT_USER/role-mappings/realm" \
          -H "Authorization: Bearer $ADMIN_TOKEN" \
          -H "Content-Type: application/json" \
          -d "$ROLES_JSON"
        echo "✓ Query/view roles assigned"
    else
        echo "⚠️  Warning: No suitable roles found to assign"
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
