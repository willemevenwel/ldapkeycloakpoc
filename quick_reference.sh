#!/bin/bash

# quick_reference.sh
# Quick reference for the new admin-only startup workflow

echo "🔧 LDAP Admin-Only Startup - Quick Reference"
echo "============================================"
echo ""
echo "📋 Current Configuration:"
echo "   - Admins loaded on startup: $(cat data/admins.csv | tail -n +2 | cut -d',' -f1 | tr '\n' ' ')"
echo "   - Total users in CSV: $(cat data/users.csv | tail -n +2 | wc -l | tr -d ' ')"
echo ""
echo "🚀 Startup Commands:"
echo "   ./start.sh                    # Start with admins only"
echo "   ./load_additional_users.sh    # Load remaining users manually"
echo "   ./stop.sh                     # Stop all services"
echo ""
echo "🧪 Development Commands:"
echo "   python3 csv_to_ldif.py help   # Show CSV converter help"
echo "   ./quick_reference.sh          # Show this reference"
echo ""
echo "📋 CSV Converter Examples:"
echo "   python3 csv_to_ldif.py data/admins.csv    # Process admin users"
echo "   python3 csv_to_ldif.py data/users.csv     # Process additional users"
echo ""
echo "🌐 Access Points:"
echo "   Web UI: http://localhost:8080  (admin/admin)"
echo "   LDAP:   ldap://localhost:389"
echo ""
echo "📝 Configuration Files:"
echo "   data/admins.csv               # Admin users (loaded on startup)"
echo "   data/users.csv                # Additional users (for manual loading)"
echo ""
echo "🔍 Verification:"
echo "   # Check loaded users:"
echo "   ldapsearch -x -H ldap://localhost:389 \\"
echo "     -D 'cn=admin,dc=mycompany,dc=local' -w admin \\"
echo "     -b 'ou=users,dc=mycompany,dc=local' \\"
echo "     '(objectClass=inetOrgPerson)' uid"
echo ""

# Check if containers are running
if docker ps | grep -q "my-openldap"; then
    echo "✅ LDAP Status: RUNNING"
    user_count=$(docker exec my-openldap ldapsearch -x -D 'cn=admin,dc=mycompany,dc=local' -w admin -b 'ou=users,dc=mycompany,dc=local' '(objectClass=inetOrgPerson)' uid 2>/dev/null | grep -c "^uid:" || echo "0")
    echo "   Current users in LDAP: $user_count"
else
    echo "❌ LDAP Status: NOT RUNNING"
    echo "   Run './start.sh' to start the system"
fi

echo "============================================"
