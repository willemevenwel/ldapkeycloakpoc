#!/bin/bash

# Simple JWT role verification script
echo "========================================="
echo "JWT ROLE VERIFICATION"
echo "========================================="

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CLIENT_SECRET="z9cTUX1Dt2ijWkWhiseOdfIb9fw10JlJ"

echo -e "${BLUE}=== CSV EXPECTATIONS ===${NC}"
echo "Willem should have: acme_ds1, xyz_ds1, xyz_ds2"
echo "Louis should have: acme_ds2"
echo ""

# Test Willem
echo -e "${YELLOW}=== WILLEM'S JWT TOKEN ===${NC}"
curl -s -X POST 'http://localhost:8090/realms/capgemini/protocol/openid-connect/token' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'username=willem' \
  -d 'password=willem' \
  -d 'grant_type=password' \
  -d 'client_id=shared-web-client' \
  -d "client_secret=${CLIENT_SECRET}" | \
  jq -r '.access_token' | cut -d'.' -f2 | base64 -d > /tmp/willem_token.json

echo "✅ Token obtained and decoded"
echo ""

echo "realm_access.roles (first 5):"
jq -r '.realm_access.roles[]' /tmp/willem_token.json 2>/dev/null | head -5 | sed 's/^/  /'

echo ""
echo "acme-roles:"
jq -r '.["acme-roles"][]' /tmp/willem_token.json 2>/dev/null | sed 's/^/  /'

echo ""
echo "xyz-roles:"
jq -r '.["xyz-roles"][]' /tmp/willem_token.json 2>/dev/null | sed 's/^/  /'

echo ""
echo "organization_enabled:"
jq -r '.organization_enabled' /tmp/willem_token.json 2>/dev/null | sed 's/^/  /'

echo ""
echo -e "${YELLOW}=== LOUIS'S JWT TOKEN ===${NC}"
curl -s -X POST 'http://localhost:8090/realms/capgemini/protocol/openid-connect/token' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'username=louis' \
  -d 'password=louis' \
  -d 'grant_type=password' \
  -d 'client_id=shared-web-client' \
  -d "client_secret=${CLIENT_SECRET}" | \
  jq -r '.access_token' | cut -d'.' -f2 | base64 -d > /tmp/louis_token.json

echo "✅ Token obtained and decoded"
echo ""

echo "realm_access.roles (first 5):"
jq -r '.realm_access.roles[]' /tmp/louis_token.json 2>/dev/null | head -5 | sed 's/^/  /'

echo ""
echo "acme-roles:"
jq -r '.["acme-roles"][]' /tmp/louis_token.json 2>/dev/null | sed 's/^/  /'

echo ""
echo "xyz-roles:"
jq -r '.["xyz-roles"][]' /tmp/louis_token.json 2>/dev/null | sed 's/^/  /'

echo ""
echo "organization_enabled:"
jq -r '.organization_enabled' /tmp/louis_token.json 2>/dev/null | sed 's/^/  /'

echo ""
echo -e "${GREEN}=== VERIFICATION COMPLETE ===${NC}"

# Cleanup
rm -f /tmp/willem_token.json /tmp/louis_token.json