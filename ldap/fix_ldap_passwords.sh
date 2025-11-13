#!/bin/bash

# Script to fix LDAP user passwords by updating them to cleartext format
# This allows Keycloak to authenticate users properly

set -e

echo "=========================================="
echo "Fixing LDAP User Passwords"
echo "=========================================="

# Read users from CSV and update their passwords
# Get script directory for relative path resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSV_FILE="${SCRIPT_DIR}/../data/users.csv"

if [ ! -f "$CSV_FILE" ]; then
    echo "Error: users.csv not found at $CSV_FILE"
    exit 1
fi

echo "Updating LDAP user passwords to cleartext format..."

# Skip header line and process each user
tail -n +2 "$CSV_FILE" | while IFS=, read -r username firstname lastname email password groups; do
    echo ""
    echo "Updating password for user: $username"
    
    # Create LDIF modification
    MODIFY_LDIF=$(cat <<EOF
dn: uid=$username,ou=users,dc=min,dc=io
changetype: modify
replace: userPassword
userPassword: $password
EOF
)
    
    # Apply the modification
    echo "$MODIFY_LDIF" | docker exec -i ldap ldapmodify -x -H ldap://localhost:389 -D "cn=admin,dc=min,dc=io" -w admin
    
    if [ $? -eq 0 ]; then
        echo "✓ Updated password for $username"
        
        # Test authentication
        if docker exec ldap ldapsearch -x -H ldap://localhost:389 -D "uid=$username,ou=users,dc=min,dc=io" -w "$password" -b "uid=$username,ou=users,dc=min,dc=io" "(objectClass=*)" dn >/dev/null 2>&1; then
            echo "✓ Authentication test passed for $username"
        else
            echo "✗ Authentication test failed for $username"
        fi
    else
        echo "✗ Failed to update password for $username"
    fi
done

echo ""
echo "=========================================="
echo "✓ Password update complete!"
echo "=========================================="
echo ""
echo "Now sync LDAP to Keycloak:"
echo "  ./keycloak/sync_ldap.sh capgemini"
echo ""
echo "Then test login with: willem / willem123P@ssword"
