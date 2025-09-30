import csv, hashlib, base64
import os
import sys

LDAP_DOMAIN = "dc=min,dc=io"
USERS_OU = "ou=users," + LDAP_DOMAIN
GROUPS_OU = "ou=groups," + LDAP_DOMAIN

# Parse command line arguments
force_mode = None
if len(sys.argv) > 1:
    arg = sys.argv[1].lower()
    if arg in ["help", "-h", "--help"]:
        print("CSV to LDIF Converter - Auto-detection support")
        print("=============================================")
        print("Usage: docker exec python-bastion python python/csv_to_ldif.py [csv_file] [mode]")
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
        print("  docker exec python-bastion python python/csv_to_ldif.py data/admins.csv    # Process admin users")
        print("  docker exec python-bastion python python/csv_to_ldif.py data/users.csv     # Process additional users")
        print("  docker exec python-bastion python python/csv_to_ldif.py data/admins.csv admins    # Force admin mode")
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



# Always generate three files: admins_only.ldif, users.ldif, group_assign.ldif
admins_ldif = os.path.join(output_dir, "admins_only.ldif")
users_ldif = os.path.join(output_dir, "users.ldif")
group_assign_ldif = os.path.join(output_dir, "group_assign.ldif")

# Remove old LDIF files if they exist
for f in [admins_ldif, users_ldif, group_assign_ldif]:
    if os.path.exists(f):
        print(f"⚠️🗑️  Deleting old LDIF file: {f}")
        os.remove(f)

print(f"Using CSV file: {input_csv}")
print(f"Output files: {admins_ldif}, {users_ldif}, {group_assign_ldif}")

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
    """Write the LDAP OU structure (base domain already exists in MinIO image)"""
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


# --- New multi-file generation logic ---
groups = {}
group_members_uids = {}
admin_groups = {}
admin_group_members_uids = {}
user_groups = {}
user_group_members_uids = {}
admins_processed = []
users_processed = []

with open(input_csv) as f:
    reader = csv.DictReader(f)
    for row in reader:
        username = row["username"]
        firstname = row["firstname"]
        lastname = row["lastname"]
        email = row["email"]
        password = sha_password(row["password"])
        is_admin = username in admin_usernames
        # Track group membership for all
        for group in row["groups"].split(";"):
            group = group.strip()
            groups.setdefault(group, []).append(f"uid={username},{USERS_OU}")
            group_members_uids.setdefault(group, []).append(username)
            if is_admin:
                admin_groups.setdefault(group, []).append(f"uid={username},{USERS_OU}")
                admin_group_members_uids.setdefault(group, []).append(username)
            else:
                user_groups.setdefault(group, []).append(f"uid={username},{USERS_OU}")
                user_group_members_uids.setdefault(group, []).append(username)
        if is_admin:
            admins_processed.append((username, firstname, lastname, email, password))
        else:
            users_processed.append((username, firstname, lastname, email, password))

# 1. Write admins_only.ldif
with open(admins_ldif, "w") as ldif:
    write_base_structure(ldif)
    for username, firstname, lastname, email, password in admins_processed:
        write_user(ldif, username, firstname, lastname, email, password)
    write_groups(ldif, admin_groups, admin_group_members_uids, 5000)

# 2. Write users.ldif
with open(users_ldif, "w") as ldif:
    for username, firstname, lastname, email, password in users_processed:
        write_user(ldif, username, firstname, lastname, email, password)
    write_groups(ldif, user_groups, user_group_members_uids, 6000)

# 3. Write group_assign.ldif (modify operations for all groups)
with open(group_assign_ldif, 'w') as modify_file:
    for group_name, member_uids in group_members_uids.items():
        group_dn = f"cn={group_name},{GROUPS_OU}"
        modify_file.write(f"# Add new members to existing group {group_name}\n")
        modify_file.write(f"dn: {group_dn}\n")
        modify_file.write("changetype: modify\n")
        modify_file.write("add: memberUid\n")
        for member_uid in member_uids:
            modify_file.write(f"memberUid: {member_uid}\n")
        modify_file.write("\n")

print(f"Admins processed: {[u[0] for u in admins_processed]}")
print(f"Users processed: {[u[0] for u in users_processed]}")
print(f"LDIF files generated: {admins_ldif}, {users_ldif}, {group_assign_ldif}")
