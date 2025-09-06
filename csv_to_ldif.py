import csv, hashlib, base64
import os
import sys

LDAP_DOMAIN = "dc=mycompany,dc=local"
USERS_OU = "ou=users," + LDAP_DOMAIN
GROUPS_OU = "ou=groups," + LDAP_DOMAIN

# Parse command line arguments
force_mode = None
if len(sys.argv) > 1:
    arg = sys.argv[1].lower()
    if arg in ["help", "-h", "--help"]:
        print("CSV to LDIF Converter - Auto-detection support")
        print("=============================================")
        print("Usage: python3 csv_to_ldif.py [csv_file] [mode]")
        print("")
        print("Arguments:")
        print("  csv_file   - Path to CSV file (default: data/users.csv)")
        print("  mode       - Optional: force mode (admins|additional)")
        print("  help       - Show this help message")
        print("")
        print("Files:")
        print("  data/admins.csv - Complete admin user data (for startup)")
        print("  data/users.csv  - Additional user data (for manual loading)")
        print("")
        print("Examples:")
        print("  python3 csv_to_ldif.py data/admins.csv    # Process admin users")
        print("  python3 csv_to_ldif.py data/users.csv     # Process additional users")
        print("  python3 csv_to_ldif.py data/admins.csv admins    # Force admin mode")
        print("")
        sys.exit(0)
    elif arg in ["admins", "additional"]:
        force_mode = arg
        input_csv = "data/users.csv" if not os.path.exists("/opt/import/users.csv") else "/opt/import/users.csv"
    else:
        # Treat as CSV file path
        input_csv = arg
        if not os.path.exists(input_csv):
            print(f"Error: CSV file '{input_csv}' not found")
            sys.exit(1)
        # Check for second argument (mode)
        if len(sys.argv) > 2 and sys.argv[2].lower() in ["admins", "additional"]:
            force_mode = sys.argv[2].lower()
else:
    # Default behavior: use users.csv
    input_csv = "data/users.csv" if not os.path.exists("/opt/import/users.csv") else "/opt/import/users.csv"

# Auto-detect if running in container or locally
if os.path.exists("/opt/import/users.csv"):
    admins_csv = "/opt/import/admins.csv"
    output_dir = "/opt/output"
    os.makedirs(output_dir, exist_ok=True)
else:
    admins_csv = "data/admins.csv"
    output_dir = "ldif"
    os.makedirs(output_dir, exist_ok=True)

# Get list of admin usernames for reference (if needed for auto-detection)
admin_usernames = set()
admin_csv_path = admins_csv if os.path.exists(admins_csv) else "data/admins.csv"
if os.path.exists(admin_csv_path):
    with open(admin_csv_path) as f:
        reader = csv.DictReader(f)
        for row in reader:
            admin_usernames.add(row["username"])

print(f"Known admin users: {', '.join(admin_usernames)}")

# Auto-detect mode based on CSV file and content (unless forced)
if force_mode:
    mode = force_mode
    print(f"Forced mode: '{mode}'")
else:
    # Auto-detect based on filename and content
    if "admins" in input_csv.lower():
        mode = "admins"
        print(f"Auto-detected mode: 'admins' (filename suggests admin users)")
    elif "users" in input_csv.lower():
        mode = "additional"
        print(f"Auto-detected mode: 'additional' (filename suggests additional users)")
    else:
        # Fallback: check content
        users_in_csv = set()
        if os.path.exists(input_csv):
            with open(input_csv) as f:
                reader = csv.DictReader(f)
                for row in reader:
                    users_in_csv.add(row["username"])

        admin_overlap = users_in_csv.intersection(admin_usernames)
        non_admin_users = users_in_csv - admin_usernames

        if admin_overlap and not non_admin_users:
            mode = "admins"
            print(f"Auto-detected mode: 'admins' (CSV contains only admin users: {', '.join(admin_overlap)})")
        elif non_admin_users and not admin_overlap:
            mode = "additional"
            print(f"Auto-detected mode: 'additional' (CSV contains only non-admin users: {', '.join(non_admin_users)})")
        elif admin_overlap and non_admin_users:
            mode = "all"
            print(f"Auto-detected mode: 'all' (CSV contains both admin and non-admin users)")
        else:
            mode = "additional"
            print(f"Auto-detected mode: 'additional' (default fallback)")

# Set output file based on detected mode
if mode == "admins":
    output_ldif = os.path.join(output_dir, "admins_only.ldif")
elif mode == "additional":
    output_ldif = os.path.join(output_dir, "additional_users.ldif")
    modify_ldif = os.path.join(output_dir, "additional_users_modify.ldif")
else:  # all
    output_ldif = os.path.join(output_dir, "users.ldif")

print(f"Using CSV file: {input_csv}")
print(f"Output file: {output_ldif}")

def sha_password(password):
    sha = hashlib.sha1(password.encode('utf-8')).digest()
    return "{SHA}" + base64.b64encode(sha).decode('utf-8')

# Get list of admin usernames from admins.csv
admin_usernames = set()
if os.path.exists(admins_csv):
    with open(admins_csv) as f:
        reader = csv.DictReader(f)
        for row in reader:
            admin_usernames.add(row["username"])

print(f"Admin users identified: {', '.join(admin_usernames)}")

def write_base_structure(ldif):
    """Write the base LDAP domain and OU structure"""
    ldif.write(f"dn: {LDAP_DOMAIN}\n")
    ldif.write("objectClass: dcObject\n")
    ldif.write("objectClass: organization\n")
    ldif.write("dc: mycompany\n")
    ldif.write("o: My Company\n\n")
    
    ldif.write(f"dn: {USERS_OU}\n")
    ldif.write("objectClass: organizationalUnit\n")
    ldif.write("ou: users\n\n")
    
    ldif.write(f"dn: {GROUPS_OU}\n")
    ldif.write("objectClass: organizationalUnit\n")
    ldif.write("ou: groups\n\n")

def write_user(ldif, username, firstname, lastname, email, password):
    """Write a user entry to LDIF"""
    user_dn = f"uid={username},{USERS_OU}"
    ldif.write(f"dn: {user_dn}\n")
    ldif.write("objectClass: inetOrgPerson\n")
    ldif.write(f"cn: {firstname} {lastname}\n")
    ldif.write(f"sn: {lastname}\n")
    ldif.write(f"givenName: {firstname}\n")
    ldif.write(f"mail: {email}\n")
    ldif.write(f"uid: {username}\n")
    ldif.write(f"userPassword: {password}\n\n")

def write_groups(ldif, groups, group_members_uids, gid_base=5000):
    """Write group entries to LDIF"""
    for idx, (group_name, members) in enumerate(groups.items()):
        group_dn = f"cn={group_name},{GROUPS_OU}"
        gid = gid_base + idx
        
        ldif.write(f"dn: {group_dn}\n")
        ldif.write("objectClass: top\n")
        ldif.write("objectClass: posixGroup\n")
        ldif.write(f"cn: {group_name}\n")
        ldif.write(f"gidNumber: {gid}\n")
        for member_uid in group_members_uids[group_name]:
            ldif.write(f"memberUid: {member_uid}\n")
        ldif.write("\n")

# Main processing logic
groups = {}
group_members_uids = {}
processed_users = []

with open(input_csv) as f, open(output_ldif, "w") as ldif:
    reader = csv.DictReader(f)
    
    # Write base structure only for 'all' and 'admins' modes
    if mode in ["all", "admins"]:
        write_base_structure(ldif)
    
    # Process users - with new structure, no filtering needed
    for row in reader:
        username = row["username"]
        firstname = row["firstname"]
        lastname = row["lastname"]
        email = row["email"]
        password = sha_password(row["password"])
        
        print(f"Processing user: {username}")
        processed_users.append(username)
        
        # Write user entry
        write_user(ldif, username, firstname, lastname, email, password)
        
        # Track group membership
        for group in row["groups"].split(";"):
            group = group.strip()
            groups.setdefault(group, []).append(f"uid={username},{USERS_OU}")
            group_members_uids.setdefault(group, []).append(username)
    
    # Write groups based on mode
    if mode == "all":
        write_groups(ldif, groups, group_members_uids, 5000)
    elif mode == "admins":
        write_groups(ldif, groups, group_members_uids, 5000)
    elif mode == "additional":
        # For additional users, create groups starting from GID 6000
        write_groups(ldif, groups, group_members_uids, 6000)

# For additional mode, also create a modify file for existing groups
if mode == "additional" and groups:
    with open(modify_ldif, 'w') as modify_file:
        for group_name, member_dns in groups.items():
            member_uids = group_members_uids[group_name]
            group_dn = f"cn={group_name},{GROUPS_OU}"
            modify_file.write(f"# Add new members to existing group {group_name}\n")
            modify_file.write(f"dn: {group_dn}\n")
            modify_file.write("changetype: modify\n")
            modify_file.write("add: memberUid\n")
            for member_uid in member_uids:
                modify_file.write(f"memberUid: {member_uid}\n")
            modify_file.write("\n")
    print(f"Modify LDIF created: {modify_ldif}")

if processed_users:
    print(f"LDIF generated successfully in '{mode}' mode!")
    print(f"Processed users: {', '.join(processed_users)}")
    print(f"Output file: {output_ldif}")
else:
    print(f"No users to process in '{mode}' mode")
