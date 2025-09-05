# LDAP Keycloak POC

A comprehensive Docker Compose setup for OpenLDAP with automated CSV to LDIF conversion, data import, and web-based user management interface.

## Table of Contents
- [Features](#features)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
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
- 🌐 **Web UI**: LDAP User Manager for browser-based administration
- 📊 **Automated CSV Import**: Convert CSV files to LDIF and import automatically
- 🎛️ **Multi-Mode Loading**: Admin-only startup with manual additional user loading
- 🔄 **Hot Reload**: Restart containers to apply CSV changes
- 🔐 **SHA Password Hashing**: Secure password storage
- 👥 **Flexible Group Management**: Support for both POSIX and standard LDAP groups
- 🚀 **Development Ready**: Complete setup for testing and development

## Project Structure

```
ldapkeycloakpoc/
├── docker-compose.yml           # Main Docker Compose configuration
├── data/
│   ├── users.csv               # User data and group memberships
│   └── admins.csv              # Admin user definitions
├── csv_to_ldif.py              # CSV to LDIF conversion script
├── ldap/
│   └── start_ldap.sh           # LDAP container startup script
├── ldap-user-manager/          # Web UI source code (from external repo)
│   ├── Dockerfile
│   ├── www/                    # PHP web application
│   └── ...
├── ldif/                       # Generated LDIF files directory
│   ├── users.ldif              # Generated user and group data
│   └── admins.ldif             # Generated admin group data
├── start.sh                    # Main startup script
├── stop.sh                     # Stop all services script
└── README.md                   # This file
```

## Prerequisites

- Docker and Docker Compose
- Python 3 (for local LDIF generation/testing)
- LDAP client tools (optional, for testing): `brew install openldap` on macOS

### Manual Build (Optional)

The docker-compose configuration will automatically build the LDAP User Manager image on first run. However, you can build it manually if needed:

```bash
# Build just the web UI container
docker-compose build ldap-webui

# Or build all containers
docker-compose build
```

**When to manually build:**
- After modifying the Dockerfile (e.g., ARM compatibility changes)
- After updating the LDAP User Manager source code
- If you want to pre-build before first run
- Troubleshooting build issues

## Quick Start

1. **Start the entire LDAP ecosystem:**
   ```bash
   ./start.sh
   ```
   
   **Note**: On first run, Docker will automatically build the LDAP User Manager image from the included Dockerfile. This may take a few minutes to download dependencies and build the PHP/Apache container.

2. **Access the services:**
   - **LDAP Server**: `ldap://localhost:389`
   - **Web UI**: http://localhost:8080

3. **Login to Web UI:**
   - **Username**: `admin`
   - **Password**: `admin`

4. **Stop everything:**
   ```bash
   ./stop.sh
   ```

## Admin-Only Startup

The system is configured to load **only admin users** on startup for better control and security.

### Startup Behavior
- **What gets loaded**: Admin users from `data/admins.csv` 
- **Result**: LDAP with complete admin user accounts for initial setup

### Loading Additional Users
After startup, manually load additional users:
```bash
./load_additional_users.sh
```

This will:
- Load all users from `data/users.csv`
- Create additional groups as needed
- Update existing group memberships

### CSV Files
- **`data/admins.csv`**: Complete admin user data (loaded on startup)
- **`data/users.csv`**: Additional user data (loaded manually)

### CSV to LDIF Converter
The `csv_to_ldif.py` script auto-detects based on filename:

```bash
# Process admin users (auto-detected from filename)
python3 csv_to_ldif.py data/admins.csv

# Process additional users (auto-detected from filename)
python3 csv_to_ldif.py data/users.csv

# Show help
python3 csv_to_ldif.py help
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
admin,Admin,User,admin@mycompany.local,admin,admins
alice,Alice,Smith,alice@mycompany.local,alice123,developers
bob,Bob,Johnson,bob@mycompany.local,bob123,admins
charlie,Charlie,Brown,charlie@mycompany.local,charlie123,developers;admins
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
username,gidNumber
admin,5000
```

This file defines which users should be in the special `admins` group for web UI administration privileges.

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

### Login Credentials

Available users (username/password):
- `admin/admin` (Admin privileges)
- `alice/alice123` (Regular user)
- `bob/bob123` (Admin privileges)
- `charlie/charlie123` (Admin privileges)

## Debugging and Troubleshooting

### Container Status and Logs

```bash
# Check running containers
docker ps

# Check all containers (including stopped)
docker ps -a

# View LDAP server logs
docker logs my-openldap

# View Web UI logs
docker logs ldap-user-manager

# Follow logs in real-time
docker logs -f my-openldap
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
- **Solution**: Check `docker logs my-openldap` for errors, ensure container is running

#### "The username and/or password are unrecognised" (Web UI)
- **Cause**: Wrong OU configuration or user doesn't exist
- **Solution**: Verify `LDAP_USER_OU=users` is set and user exists in `ou=users`

#### Container exits immediately
- **Cause**: Script error in startup
- **Solution**: Check `docker logs my-openldap` for specific errors

#### "Invalid syntax" errors during LDAP import
- **Cause**: Malformed LDIF or unsupported object class combinations
- **Solution**: Check generated LDIF files in `ldif/` directory

### Manual CSV to LDIF Conversion

For debugging the conversion process:

```bash
# Generate LDIF manually
python3 csv_to_ldif.py

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

If you need `groupOfNames` instead (uses full DN membership), modify `csv_to_ldif.py`:

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
# From csv_to_ldif.py
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

To change the LDAP structure, edit `csv_to_ldif.py`:

1. **Change base domain**: Modify `LDAP_DOMAIN` variable
2. **Change OUs**: Modify `USERS_OU` and `GROUPS_OU` variables
3. **Add user attributes**: Extend the user creation section
4. **Change group types**: Modify group object classes and attributes

## Development Notes

### Startup Sequence
1. `start.sh` → `docker-compose up -d`
2. LDAP container starts with Alpine Linux
3. `start_ldap.sh` runs inside container:
   - Installs OpenLDAP, Python, and dependencies
   - Creates LDAP configuration with MDB backend and NIS schema
   - Runs `csv_to_ldif.py` to convert CSV to LDIF
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
