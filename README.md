# LDAP Keycloak POC

A comprehensive Docker Compose setup for OpenLDAP with automated CSV to LDIF conversion, data import, Keycloak integration, and web-based user management interface.

## Table of Contents
- [Features](#features)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Keycloak Integration](#keycloak-integration)
- [Admin-Only Startup](#admin-only-startup)
- [LDAP Configuration](#ldap-configuration)
- [User and Group Management](#user-and-group-management)
- [Web UI Management](#web-ui-management)
- [Debugging and Troubleshooting](#debugging-and-troubleshooting)
- [LDAP Group Types and Compatibility](#ldap-group-types-and-compatibility)
- [CSV File Structure and Influence](#csv-file-structure-and-influence)
- [Development Notes](#development-notes)
- [Attribution and Credits](#attribution-and-credits)

## Features

- 🔒 **OpenLDAP Server**: Running on Alpine Linux with MDB backend
- 🔐 **Keycloak Identity Provider**: Enterprise-grade identity and access management
- 🌐 **Web UI**: LDAP User Manager for browser-based administration
- 📊 **Automated CSV Import**: Convert CSV files to LDIF and import automatically
- 🎛️ **Multi-Mode Loading**: Admin-only startup with manual additional user loading
- 🔄 **Hot Reload**: Restart containers to apply CSV changes
- 🔐 **SHA Password Hashing**: Secure password storage
- 👥 **Flexible Group Management**: Support for both POSIX and standard LDAP groups
- 🚀 **Development Ready**: Complete setup for testing and development
- 🏢 **User Federation**: Automated LDAP provider setup for Keycloak realms

## Project Structure

```
ldapkeycloakpoc/
├── docker-compose.yml           # Main Docker Compose configuration
├── data/
│   ├── users.csv               # User data and group memberships
│   └── admins.csv              # Admin user definitions
├── python/
│   └── csv_to_ldif.py          # CSV to LDIF conversion script
├── keycloak/                   # Keycloak management scripts
│   ├── create_realm.sh         # Create new Keycloak realms
│   ├── add_ldap_provider_for_keycloak.sh  # Configure LDAP user federation
│   └── debug_realm_ldap.sh     # Debug realm and LDAP provider status
├── ldap/
│   ├── setup_ldap_data.sh      # LDAP container startup script  
│   └── load_additional_users.sh # Load additional users after startup
├── ldap-user-manager/          # Web UI source code (from external repo)
│   ├── Dockerfile
│   ├── www/                    # PHP web application
│   └── ...
├── ldif/                       # Generated LDIF files directory
│   ├── users.ldif              # Generated user and group data
│   └── admins.ldif             # Generated admin group data
├── start.sh                    # Main startup script
├── stop.sh                     # Stop all services script
├── start_all.sh                # Traditional complete setup script
├── test_all.sh                 # Verification script for setup
├── load_additional_users.sh    # Load additional users after startup
└── README.md                   # This file
```

## Prerequisites

- Docker and Docker Compose
- LDAP client tools (optional, for testing): `brew install openldap` on macOS

### Cross-Platform Support 🚀

**All Python execution is now containerized!** No need to install Python locally on any platform.

**Perfect for:**
- ✅ **Windows users** (no need for WSL or Linux tools)
- ✅ **Users without Python installed**
- ✅ **Consistent execution environment** across all platforms
- ✅ **No dependency management hassles**
- ✅ **Direct containerized execution via Docker commands**

### Usage Methods

**All platforms use the same Docker-based approach:**

```bash
# Complete LDAP-Keycloak setup
./start_all.sh mycompany

# Interactive setup with confirmations
./start_all.sh mycompany --check-steps

# LDAP-only setup
./start.sh

# Load additional users
./ldap/load_additional_users.sh

# Generate LDIF manually
docker exec python-bastion python python/csv_to_ldif.py data/admins.csv

# Get help
docker exec python-bastion python python/csv_to_ldif.py help

# Interactive shell in container
docker exec -it python-bastion bash
```

### Docker Compose Services

The project now includes four containers:
- **ldap**: OpenLDAP server
- **ldap-manager**: Web-based LDAP management interface  
- **keycloak**: Identity and access management
- **utils**: Python utilities container (for cross-platform script execution)

### Manual Build (Optional)

The docker-compose configuration will automatically build the LDAP User Manager image on first run. However, you can build it manually if needed:

```bash
# Build just the web UI container
docker-compose build ldap-manager

# Or build all containers
docker-compose build
```

**When to manually build:**
- After modifying the Dockerfile (e.g., ARM compatibility changes)
- After updating the LDAP User Manager source code
- If you want to pre-build before first run
- Troubleshooting build issues

## Quick Start

### Complete LDAP-Keycloak Setup

**All platforms use the same approach:**
```bash
# Complete automated setup with realm creation and LDAP integration
./start_all.sh <realm-name>

# Interactive mode with step-by-step confirmation
./start_all.sh <realm-name> --check-steps
```

**Example:**
```bash
# Set up everything for "mycompany" realm
./start_all.sh mycompany
```

### LDAP-Only Setup

**Start LDAP services only (no Keycloak realm setup):**
```bash
./start.sh
```
   
   **Note**: On first run, Docker will automatically build the LDAP User Manager image from the included Dockerfile. This may take a few minutes to download dependencies and build the PHP/Apache container.

2. **Access the services:**
   - **LDAP Server Protocol**: `ldap://localhost:389`
   - **LDAP Web Manager**: http://localhost:8091
   - **Keycloak**: http://localhost:8090

3. **Login credentials:**
   - **LDAP Web Manager (web UI)**: `admin` / `admin`
   - **LDAP Server (protocol)**: `cn=admin,dc=mycompany,dc=local` / `admin`

4. **Login to Keycloak:**
   - **Username**: `admin`
   - **Password**: `admin`

5. **Stop everything:**
   ```bash
   ./stop.sh
   ```

## Keycloak Integration

This POC includes Keycloak for enterprise identity and access management with LDAP user federation.

### Keycloak Access
- **URL**: http://localhost:8090
- **Admin Console**: http://localhost:8090/admin/
- **Master Admin**: `admin` / `admin`

### Realm Management

#### Creating a New Realm
```bash
# Create a new realm (e.g., "company")
./keycloak/create_realm.sh company
```

This creates:
- New realm named "company"
- Admin user: `admin-company` / `admin-company`
- Proper realm configuration for LDAP integration

#### Complete Automated Setup
```bash
# Complete setup: services + realm + LDAP provider + role mapping + sync
./start_all.sh company

# Interactive mode with step-by-step confirmation
./start_all.sh company --check-steps
```

#### Manual Step-by-Step Setup
```bash
# 1. Add LDAP provider to a realm
./keycloak/add_ldap_provider_for_keycloak.sh company

# 2. Create role mapper for LDAP groups → Keycloak roles
./keycloak/update_role_mapper.sh company

# 3. Sync users and roles from LDAP
./keycloak/sync_ldap.sh company
```

#### LDAP Integration Features
This automatically configures:
- LDAP connection to the local OpenLDAP server
- User import from `ou=users,dc=mycompany,dc=local`
- **Role mapping** from `ou=groups,dc=mycompany,dc=local` to Keycloak roles
- Read-only federation (users managed in LDAP)
- Anticipated role creation (admin, developer, ds_member, user)
- POSIX group mapping for group membership

#### LDAP Provider Configuration Details

The script configures the following LDAP settings:
- **Connection URL**: `ldap://ldap:389`
- **Users DN**: `ou=users,dc=mycompany,dc=local`
- **Bind DN**: `cn=admin,dc=mycompany,dc=local`
- **Bind Credential**: `admin`
- **User Object Classes**: `inetOrgPerson`
- **Username Attribute**: `uid`
- **UUID Attribute**: `entryUUID`
- **Edit Mode**: `READ_ONLY`
- **Import Enabled**: `true`
- **Sync Registrations**: `true`

### Keycloak Debugging

#### Check Realm and LDAP Provider Status
```bash
# Debug a specific realm
./keycloak/debug_realm_ldap.sh company
```

Output example:
```
🔍 Checking realm: company
✅ Realm company exists and is accessible
✅ Found 1 LDAP provider(s) in realm company:
{
  "id": "abc123def456",
  "name": "ldap-provider",
  "enabled": "true"
}
```

#### Role Mapping Configuration
```bash
# Create role mapper to map LDAP groups to Keycloak roles
./keycloak/update_role_mapper.sh company
```

This creates a role-ldap-mapper that:
- Maps LDAP groups (`admins`, `developers`, etc.) to Keycloak roles
- Automatically creates anticipated roles if they don't exist
- Syncs group membership to role assignment

#### LDAP Synchronization
```bash
# Sync users and roles from LDAP to Keycloak
./keycloak/sync_ldap.sh company
```

The sync script:
- Triggers full user synchronization from LDAP
- Syncs role assignments based on LDAP group membership
- Provides detailed status and error reporting
- Lists current users and roles after sync

#### Manual Verification
Access the Keycloak Admin Console:
1. Go to http://localhost:8090/admin/
2. Login with master admin (`admin` / `admin`)
3. Select your realm from the dropdown
4. Navigate to **User Federation** → verify LDAP provider
5. Navigate to **Realm Roles** → verify synced roles
6. Navigate to **Users** → verify synced users and role assignments

#### Common Keycloak URLs
```bash
# Realm-specific URLs (replace 'company' with your realm name)
# Realm public endpoint
http://localhost:8090/realms/company

# Realm admin console
http://localhost:8090/admin/company/console/

# User federation management
http://localhost:8090/admin/company/console/#/company/user-federation

# Users management
http://localhost:8090/admin/company/console/#/company/users
```

### Troubleshooting Keycloak Integration

#### LDAP Provider Not Visible in UI
If the LDAP provider doesn't appear in the Keycloak Admin Console:
1. **Check provider exists via API**:
   ```bash
   ./keycloak/debug_realm_ldap.sh <realm-name>
   ```
2. **Clear browser cache** (Ctrl+F5 or Cmd+Shift+R)
3. **Try incognito/private browsing mode**
4. **Verify correct realm** in the Keycloak admin console

#### Connection Issues
If Keycloak can't connect to LDAP:
1. **Verify LDAP is running**:
   ```bash
   docker ps | grep ldap
   docker logs ldap
   ```
2. **Test LDAP connectivity**:
   ```bash
   docker exec keycloak ping ldap
   ```
3. **Check LDAP data**:
   ```bash
   ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=mycompany,dc=local" -w admin -b "ou=users,dc=mycompany,dc=local"
   ```

#### User Import Issues
If users don't sync from LDAP:
1. **Trigger manual sync** in Keycloak Admin Console:
   - Go to User Federation → ldap-provider
   - Click "Sync all users"
2. **Check LDAP user format** matches expected schema
3. **Verify user DN structure** in LDAP matches Keycloak configuration

## Admin-Only Startup

The system is configured to load **only admin users** on startup for better control and security.

### Startup Behavior
- **What gets loaded**: Admin users from `data/admins.csv` 
- **Result**: LDAP with complete admin user accounts for initial setup

### Loading Additional Users
After startup, manually load additional users:

```bash
./ldap/load_additional_users.sh
```

This will:
- Load all users from `data/users.csv`
- Create additional groups as needed
- Update existing group memberships
- **Prompt to sync LDAP to Keycloak** (if using Keycloak integration)

## LDAP Configuration

## Cross-Platform Utilities

### CSV Files
- **`data/admins.csv`**: Complete admin user data (loaded on startup)
- **`data/users.csv`**: Additional user data (loaded manually)

### CSV to LDIF Converter
The `python/csv_to_ldif.py` script auto-detects based on filename:

**Containerized Method:**
```bash
# Process admin users (auto-detected from filename)
docker exec python-bastion python python/csv_to_ldif.py data/admins.csv

# Process additional users (auto-detected from filename)
docker exec python-bastion python python/csv_to_ldif.py data/users.csv

# Show help
docker exec python-bastion python python/csv_to_ldif.py help
```

## LDAP Configuration

### Server Details
- **Domain**: `mycompany.local`
- **Base DN**: `dc=mycompany,dc=local`
- **Root Admin DN**: `cn=admin,dc=mycompany,dc=local`
- **Root Admin Password**: `admin`
- **Users OU**: `ou=users,dc=mycompany,dc=local`
- **Groups OU**: `ou=groups,dc=mycompany,dc=local`

### Schema Configuration
The LDAP server loads the following schemas:
- `core.schema` - Basic LDAP object classes
- `cosine.schema` - Additional standard attributes
- `inetorgperson.schema` - Person object classes and attributes
- `nis.schema` - POSIX/Unix integration (for posixGroup support)

### Directory Structure
```
dc=mycompany,dc=local
├── ou=users,dc=mycompany,dc=local
│   ├── uid=admin,ou=users,dc=mycompany,dc=local
│   ├── uid=alice,ou=users,dc=mycompany,dc=local
│   ├── uid=bob,ou=users,dc=mycompany,dc=local
│   └── uid=charlie,ou=users,dc=mycompany,dc=local
└── ou=groups,dc=mycompany,dc=local
    ├── cn=admins,ou=groups,dc=mycompany,dc=local
    └── cn=developers,ou=groups,dc=mycompany,dc=local
```

## User and Group Management

### CSV File Structure

#### `data/users.csv`
```csv
username,firstname,lastname,email,password,groups
alice,Alice,Smith,alice@mycompany.local,alice123,developers
bob,Bob,Johnson,bob@mycompany.local,bob123,developers
charlie,Charlie,Brown,charlie@mycompany.local,charlie123,developers
```

**Field Descriptions:**
- `username`: Unique identifier (becomes `uid` in LDAP)
- `firstname`: User's given name (`givenName` attribute)
- `lastname`: User's surname (`sn` attribute)
- `email`: Email address (`mail` attribute)
- `password`: Plain text password (automatically SHA-hashed)
- `groups`: Semicolon-separated group list for membership

#### `data/admins.csv`
```csv
username,firstname,lastname,email,password,groups,gidNumber
admin,Admin,User,admin@mycompany.local,admin,admins,5000
```

This file defines which users should be in the special `admins` group for web UI administration privileges.

**Note on gidNumber**: The value 5000 is the Group ID for the "admins" group in LDAP. Starting at 5000 avoids conflicts with system groups (0-999) and reserved ranges (1000-4999), following Unix/Linux conventions. Additional groups get sequential IDs (5001, 5002, etc.).

### User Object Classes and Attributes

Each user is created with:
- **Object Class**: `inetOrgPerson`
- **Attributes**:
  - `uid`: Username
  - `cn`: Full name (firstname + lastname)
  - `givenName`: First name
  - `sn`: Last name
  - `mail`: Email address
  - `userPassword`: SHA-hashed password

### Applying Changes

After editing CSV files:
```bash
./stop.sh
./start.sh
```

## Web UI Management

### LDAP User Manager Configuration

The web UI is configured via environment variables in `docker-compose.yml`:

```yaml
environment:
  - LDAP_URI=ldap://ldap:389                    # LDAP server connection
  - LDAP_BASE_DN=dc=mycompany,dc=local          # Base search DN
  - LDAP_USER_OU=users                          # Users organizational unit
  - LDAP_GROUP_OU=groups                        # Groups organizational unit
  - LDAP_ADMINS_GROUP=admins                    # Admin group name
  - LDAP_ADMIN_BIND_DN=cn=admin,dc=mycompany,dc=local  # Admin bind DN
  - LDAP_ADMIN_BIND_PWD=admin                   # Admin bind password
  - LDAP_REQUIRE_STARTTLS=FALSE                 # Disable TLS for development
  - NO_HTTPS=true                               # Disable HTTPS for development
```

### Web UI Expectations

The LDAP User Manager expects:
1. **User Location**: Users must be in `ou=users,dc=mycompany,dc=local`
2. **Group Location**: Groups must be in `ou=groups,dc=mycompany,dc=local`
3. **Admin Group**: Users in the `admins` group get administrative privileges
4. **User Object Class**: Users should be `inetOrgPerson` objects
5. **Group Object Class**: Groups should be `posixGroup` objects

### Group Name Validation

The LDAP User Manager includes system name validation that can restrict group and user names to specific patterns. This is controlled by the `ENFORCE_SAFE_SYSTEM_NAMES` environment variable:

```yaml
environment:
  - ENFORCE_SAFE_SYSTEM_NAMES=FALSE    # Disable strict name validation
```

**When validation is enabled (TRUE):**
- Group and user names must match the regex: `^[a-z][a-zA-Z0-9\._-]{3,32}$`
- Must start with lowercase letter
- Length between 3-32 characters
- Only allows alphanumeric, dot, underscore, and hyphen

**When validation is disabled (FALSE):**
- More flexible naming conventions allowed
- Useful for existing LDAP data with different naming patterns
- Recommended for POC/development environments

**Note**: This setting is disabled in the current configuration to allow group names like `ds1`, `ds2`, `ds3` to work properly with the web interface.

### Login Credentials

Available users (username/password):
- `admin/admin` (Admin privileges)
- `alice/alice123` (Regular user)
- `bob/bob123` (Admin privileges)
- `charlie/charlie123` (Admin privileges)

## Container Access

You can access the running containers directly using docker exec for debugging and administration:

```bash
# Access the LDAP container (Alpine Linux with shell)
docker exec -it ldap sh

# Access the LDAP Manager container (Ubuntu with bash)
docker exec -it ldap-manager bash

# Run specific commands without entering the container
docker exec ldap ps aux                    # Check processes in LDAP container
docker exec ldap-manager ps aux           # Check processes in LDAP Manager container

# Check LDAP service status and data
docker exec ldap netstat -tlnp            # Check what ports are listening
docker exec ldap ldapsearch -x -b "dc=mycompany,dc=local" -D "cn=admin,dc=mycompany,dc=local" -w admin

# Check Apache and PHP status in LDAP Manager
docker exec ldap-manager service apache2 status
docker exec ldap-manager php -v
```

## Debugging and Troubleshooting

### Container Status and Logs

```bash
# Check running containers
docker ps

# Check all containers (including stopped)
docker ps -a

# View LDAP server logs
docker logs ldap

# View LDAP Web UI logs
docker logs ldap-manager

# View Keycloak logs
docker logs keycloak

# Follow logs in real-time
docker logs -f ldap
docker logs -f keycloak

# Get detailed container information
docker inspect ldap
docker inspect ldap-manager
docker inspect keycloak
```

### Interactive Container Debugging

```bash
# Debug LDAP service inside container
docker exec -it ldap sh -c "ps aux | grep slapd"
docker exec -it ldap sh -c "netstat -tlnp"

# Debug LDAP web service inside container  
docker exec -it ldap-manager bash -c "ps aux | grep apache"
docker exec -it ldap-manager bash -c "tail -f /var/log/apache2/error.log"

# Debug Keycloak service inside container
docker exec -it keycloak bash -c "ps aux | grep java"
docker exec -it keycloak bash -c "netstat -tlnp"

# Test LDAP from inside containers
docker exec ldap ldapsearch -x -b "dc=mycompany,dc=local" -D "cn=admin,dc=mycompany,dc=local" -w admin
docker exec keycloak curl -s http://ldap:389 || echo "LDAP connection failed"
```

### Keycloak-Specific Debugging

```bash
# Check Keycloak startup logs
docker logs keycloak | grep -E "(started|error|exception)"

# Test Keycloak admin API
curl -s "http://localhost:8090/admin/master/console/" | grep -o "<title>.*</title>"

# Check Keycloak realms
curl -s "http://localhost:8090/realms/master" | jq '.realm' 2>/dev/null || echo "Master realm not responding"

# Debug specific realm (replace 'company' with your realm)
./keycloak/debug_realm_ldap.sh company

# Manual API check for LDAP providers in a realm
REALM="company"
TOKEN=$(curl -s -X POST "http://localhost:8090/realms/${REALM}/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=admin-${REALM}" \
    -d "password=admin-${REALM}" \
    -d "grant_type=password" \
    -d "client_id=admin-cli" | jq -r '.access_token')

curl -s -X GET "http://localhost:8090/admin/realms/${REALM}/components?type=org.keycloak.storage.UserStorageProvider" \
    -H "Authorization: Bearer ${TOKEN}" | jq '.'
```

### Quick Debug Commands Reference

```bash
# Most common debugging commands
docker ps                                    # Check if containers are running
docker logs ldap                            # Check LDAP container logs
docker logs ldap-manager                    # Check LDAP web UI logs
docker logs keycloak                        # Check Keycloak logs
docker exec -it ldap sh                     # Enter LDAP container
docker exec -it ldap-manager bash           # Enter LDAP web UI container
docker exec -it keycloak bash               # Enter Keycloak container

# Quick health checks
docker exec ldap ps aux | grep slapd        # Check if LDAP daemon is running
docker exec ldap-manager ps aux | grep apache  # Check if Apache is running
docker exec keycloak ps aux | grep java     # Check if Keycloak is running

# Keycloak realm and LDAP debugging
./keycloak/debug_realm_ldap.sh <realm-name> # Check realm and LDAP provider status
```

### LDAP Server Testing

```bash
# Test basic connection
ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=mycompany,dc=local" -w admin -s base

# Search all entries
ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=mycompany,dc=local" -w admin -b "dc=mycompany,dc=local" "(objectClass=*)"

# Search users only
ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=mycompany,dc=local" -w admin -b "ou=users,dc=mycompany,dc=local" "(objectClass=inetOrgPerson)"

# Search groups only
ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=mycompany,dc=local" -w admin -b "ou=groups,dc=mycompany,dc=local" "(objectClass=posixGroup)"

# Test user authentication
ldapsearch -x -H ldap://localhost:389 -D "uid=admin,ou=users,dc=mycompany,dc=local" -w admin -b "dc=mycompany,dc=local" "(uid=admin)"
```

### Common Issues and Solutions

#### "Failed to bind as cn=admin,dc=mycompany,dc=local"
- **Cause**: LDAP server not running or wrong credentials
- **Solution**: Check `docker logs ldap` for errors, ensure container is running

#### "The username and/or password are unrecognised" (LDAP Web UI)
- **Cause**: Wrong OU configuration or user doesn't exist
- **Solution**: Verify `LDAP_USER_OU=users` is set and user exists in `ou=users`

#### Keycloak "Connection refused" or not accessible
- **Cause**: Keycloak container not running or port conflict
- **Solution**: 
  ```bash
  docker ps | grep keycloak              # Check if running
  docker logs keycloak                   # Check startup logs
  netstat -tlnp | grep 8090              # Check if port is in use
  ```

#### LDAP provider not visible in Keycloak UI
- **Cause**: Provider created with wrong realm ID or UI cache
- **Solution**: 
  ```bash
  ./keycloak/debug_realm_ldap.sh <realm-name>  # Verify provider exists
  # Clear browser cache and try incognito mode
  # Check Keycloak logs for any federation errors
  ```

#### Keycloak can't connect to LDAP
- **Cause**: Network connectivity or LDAP credentials
- **Solution**:
  ```bash
  docker exec keycloak ping ldap         # Test network connectivity
  docker logs ldap | grep -i error       # Check LDAP errors
  # Verify LDAP bind credentials in Keycloak configuration
  ```

#### Users not syncing from LDAP to Keycloak
- **Cause**: LDAP schema mismatch or sync not triggered
- **Solution**:
  - Manually trigger sync in Keycloak Admin Console
  - Verify user object classes match (inetOrgPerson)
  - Check LDAP user DN structure matches Keycloak expectations

#### Container exits immediately
- **Cause**: Script error in startup
- **Solution**: Check `docker logs <container-name>` for specific errors

### Manual CSV to LDIF Conversion

For debugging the conversion process:

```bash
# Generate LDIF manually
docker exec python-bastion python python/csv_to_ldif.py

# Check generated files
cat ldif/users.ldif
cat ldif/admins.ldif

# Test import manually (with running LDAP server)
ldapadd -x -H ldap://localhost:389 -D "cn=admin,dc=mycompany,dc=local" -w admin -f ldif/users.ldif
```

## LDAP Group Types and Compatibility

### Group Object Classes Used

This setup uses **`posixGroup`** object class for groups, which provides:
- Unix/Linux compatibility
- Simple membership via `memberUid` attribute
- GID number support for POSIX systems
- Wide compatibility with LDAP management tools

### Why posixGroup?

1. **Compatibility**: Works with most LDAP user management interfaces
2. **Simplicity**: Uses username-based membership (`memberUid`)
3. **Unix Integration**: Compatible with POSIX systems
4. **Schema Support**: Widely supported across LDAP implementations

### Group Attributes

Each group contains:
- `objectClass: posixGroup`
- `cn`: Group name
- `gidNumber`: Unique group ID number
- `memberUid`: List of usernames (not full DNs)

### Alternative: groupOfNames

If you need `groupOfNames` instead (uses full DN membership), modify `python/csv_to_ldif.py`:

```python
# Change this line:
ldif.write("objectClass: posixGroup\n")

# To this:
ldif.write("objectClass: groupOfNames\n")

# And change membership format from:
ldif.write(f"memberUid: {member_uid}\n")

# To:
ldif.write(f"member: uid={member_uid},{USERS_OU}\n")
```

## CSV File Structure and Influence

### How CSV Files Control LDAP Structure

#### `data/users.csv` Impact:
1. **User Creation**: Each row creates a user in `ou=users`
2. **Group Creation**: Groups listed in `groups` column are automatically created
3. **Group Membership**: Users are added to specified groups
4. **Password Hashing**: Plain text passwords are converted to SHA hashes
5. **Attribute Mapping**:
   - `username` → `uid`
   - `firstname` → `givenName`
   - `lastname` → `sn`
   - `email` → `mail`
   - `password` → `userPassword` (SHA-hashed)

#### `data/admins.csv` Impact:
1. **Admin Group Creation**: Creates/updates the `admins` group
2. **Admin Membership**: Adds specified users to admin group
3. **GID Assignment**: Sets the group ID number for the admin group

### Group Membership Logic

Groups are created dynamically based on CSV content:
```python
# From python/csv_to_ldif.py
for group in row["groups"].split(";"):
    group = group.strip()
    groups.setdefault(group, []).append(user_dn)
    group_members_uids.setdefault(group, []).append(username)
```

This means:
- New groups are created automatically when referenced
- GID numbers are assigned sequentially (starting from 5000)
- Users can be in multiple groups (semicolon-separated)

### Modifying User/Group Structure

To change the LDAP structure, edit `python/csv_to_ldif.py`:

1. **Change base domain**: Modify `LDAP_DOMAIN` variable
2. **Change OUs**: Modify `USERS_OU` and `GROUPS_OU` variables
3. **Add user attributes**: Extend the user creation section
4. **Change group types**: Modify group object classes and attributes

## Development Notes

### Startup Sequence
1. `start.sh` → `docker-compose up -d`
2. LDAP container starts with Alpine Linux
   - Installs OpenLDAP, Python, and dependencies
   - Creates LDAP configuration with MDB backend and NIS schema
   - Runs `python/csv_to_ldif.py` to convert CSV to LDIF
   - Starts LDAP server
   - Imports generated LDIF files
4. Web UI container starts and connects to LDAP server

### Key Configuration Decisions

1. **posixGroup over groupOfNames**: Better compatibility with management tools
2. **NIS schema inclusion**: Required for posixGroup support
3. **SHA password hashing**: Balance of security and compatibility
4. **Separate admin CSV**: Allows for flexible admin group management
5. **Environment variable configuration**: Makes web UI configuration flexible

### Security Considerations

⚠️ **This is a development/testing setup:**
- Default passwords used throughout
- No SSL/TLS encryption
- No access controls beyond basic authentication
- Passwords stored in plain text in CSV files
- Suitable for POC and development only

For production:
- Change all default passwords
- Implement LDAPS (LDAP over SSL)
- Use proper authentication mechanisms
- Implement access controls
- Use Docker secrets for sensitive data
- Hash passwords before storing in CSV

## Attribution and Credits

### LDAP User Manager

This project includes the **LDAP User Manager** web interface created by wheelybird.

- **Original Repository**: https://github.com/wheelybird/ldap-user-manager
- **License**: MIT License
- **Purpose**: Provides a web-based interface for managing LDAP users and groups

#### Updating the Web UI

If you want to update or modify the LDAP User Manager:

1. **Check out the original repository**:
   ```bash
   # Remove the current version
   rm -rf ldap-user-manager/
   
   # Clone the latest version
   git clone https://github.com/wheelybird/ldap-user-manager.git
   ```

2. **Remove git references to avoid submodule issues**:
   ```bash
   cd ldap-user-manager/
   rm -rf .git .github .gitignore
   cd ..
   
   # Re-add as regular files to your project
   git rm --cached -f ldap-user-manager  # If it was tracked as submodule
   git add ldap-user-manager/
   ```

3. **Fix ARM/Mac compatibility (if needed)**:
   If you're on Apple Silicon (M1/M2) or ARM architecture, you need to modify the Dockerfile:
   ```bash
   # Edit ldap-user-manager/Dockerfile
   # Find this line:
   docker-php-ext-configure ldap --with-libdir=lib/x86_64-linux-gnu && \
   
   # Change it to:
   docker-php-ext-configure ldap --with-libdir=lib/aarch64-linux-gnu && \
   ```
   
   This configures the PHP LDAP extension to use the correct library path for ARM architecture.

4. **Rebuild the Docker image**:
   ```bash
   docker-compose build ldap-webui
   # Or restart with automatic rebuild
   docker-compose up -d --build
   ```

#### Why Remove Git References?

The original LDAP User Manager is a separate git repository. When included in your project:
- Git may treat it as a submodule
- This can cause confusing git status messages
- Submodule management adds complexity

By removing the `.git` directory, the code becomes part of your main repository as regular files, avoiding submodule complexity while still giving proper credit to the original authors.

### Other Credits

- **OpenLDAP**: The LDAP server implementation
- **Alpine Linux**: Minimal container base image
- **Docker**: Containerization platform

## License

This POC project configuration is provided as-is for educational and development purposes. Please respect the licenses of the included components:
- LDAP User Manager: MIT License
- OpenLDAP: OpenLDAP Public License
- Alpine Linux: Various open source licenses
