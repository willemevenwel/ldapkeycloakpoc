import csv, hashlib, base64
import os

LDAP_DOMAIN = "dc=mycompany,dc=local"
USERS_OU = "ou=users," + LDAP_DOMAIN
GROUPS_OU = "ou=groups," + LDAP_DOMAIN


# Auto-detect if running in container or locally
if os.path.exists("/opt/import/users.csv"):
    users_csv = "/opt/import/users.csv"
    admins_csv = "/opt/import/admins.csv"
    users_ldif = "/opt/output/users.ldif"
    admins_ldif = "/opt/output/admins.ldif"
    os.makedirs("/opt/output", exist_ok=True)
else:
    users_csv = "data/users.csv"
    admins_csv = "data/admins.csv"
    users_ldif = "ldif/users.ldif"
    admins_ldif = "ldif/admins.ldif"
    os.makedirs("ldif", exist_ok=True)

def sha_password(password):
    sha = hashlib.sha1(password.encode('utf-8')).digest()
    return "{SHA}" + base64.b64encode(sha).decode('utf-8')

# --- USERS & GROUPS LDIF ---
groups = {}
group_members_uids = {}
with open(users_csv) as f, open(users_ldif, "w") as ldif:
    reader = csv.DictReader(f)
    # Create base domain entry first
    ldif.write(f"dn: {LDAP_DOMAIN}\nobjectClass: dcObject\nobjectClass: organization\ndc: mycompany\no: My Company\n\n")
    # Create top-level OUs
    ldif.write(f"dn: {USERS_OU}\nobjectClass: organizationalUnit\nou: users\n\n")
    ldif.write(f"dn: {GROUPS_OU}\nobjectClass: organizationalUnit\nou: groups\n\n")
    for row in reader:
        username = row["username"]
        firstname = row["firstname"]
        lastname = row["lastname"]
        email = row["email"]
        password = sha_password(row["password"])
        user_dn = f"uid={username},{USERS_OU}"
        # Add user entry
        ldif.write(f"dn: {user_dn}\n")
        ldif.write("objectClass: inetOrgPerson\n")
        ldif.write(f"cn: {firstname} {lastname}\n")
        ldif.write(f"sn: {lastname}\n")
        ldif.write(f"givenName: {firstname}\n")
        ldif.write(f"mail: {email}\n")
        ldif.write(f"uid: {username}\n")
        ldif.write(f"userPassword: {password}\n\n")
        # Track group membership
        for group in row["groups"].split(";"):
            group = group.strip()
            groups.setdefault(group, []).append(user_dn)
            group_members_uids.setdefault(group, []).append(username)
    # Add groups (using posixGroup only for better compatibility)
    gid_base = 5000
    for idx, (group_name, members) in enumerate(groups.items()):
        group_dn = f"cn={group_name},{GROUPS_OU}"
        gid = gid_base + idx
        # Single entry with posixGroup objectClass
        ldif.write(f"dn: {group_dn}\n")
        ldif.write("objectClass: posixGroup\n")
        ldif.write(f"cn: {group_name}\n")
        ldif.write(f"gidNumber: {gid}\n")
        for member_uid in group_members_uids[group_name]:
            ldif.write(f"memberUid: {member_uid}\n")
        ldif.write("\n")

# --- ADMINS LDIF ---
if os.path.exists(admins_csv):
    admin_members = []
    admin_member_uids = []
    with open(admins_csv) as f:
        reader = csv.DictReader(f)
        for row in reader:
            username = row["username"]
            admin_member_uids.append(username)
            # Assume admin users exist in the users OU
            admin_members.append(f"uid={username},{USERS_OU}")
    
    # Create a single admin group entry if we have members
    if admin_member_uids:
        with open(admins_ldif, "w") as ldif:
            ldif.write(f"dn: cn=admins,{GROUPS_OU}\n")
            ldif.write("objectClass: posixGroup\n")
            ldif.write("cn: admins\n")
            ldif.write("gidNumber: 5000\n")
            for member_uid in admin_member_uids:
                ldif.write(f"memberUid: {member_uid}\n")
            ldif.write("\n")

print("LDIF files generated successfully!")
