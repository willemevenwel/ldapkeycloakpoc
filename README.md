# LDAP Keycloak POC

A comprehensive Docker Compose setup for OpenLDAP with automated CSV to LDIF conversion, data import, Keycloak integration, and web-based user management interface.

## Quick Start

### Complete LDAP-Keycloak Setup (Recommended: Container-Based)

**🚀 Enhanced Container-Based Approach (All Platforms):**
```bash
# Complete automated setup with realm creation and LDAP integration
./start_all_bastion.sh <realm-name>

# Fully automated with all defaults
./start_all_bastion.sh <realm-name> --defaults

# Interactive mode with step-by-step confirmation
./start_all_bastion.sh <realm-name> --check-steps
```

**Example:**
```bash
# Set up everything for "mycompany" realm
./start_all_bastion.sh mycompany --defaults
```

**Benefits of Container-Based Approach:**
- ✅ **Eliminates Windows/WSL/Git Bash compatibility issues**
- ✅ **Clean professional output** - no messy package installation feedback
- ✅ **Pre-installed tools** - docker, curl, jq, ldap-utils ready immediately
- ✅ **Automatic network detection** - uses service names in containers, localhost on host
- ✅ **Cross-platform reliability** - identical behavior on Windows/macOS/Linux

### Alternative: Traditional Host-Based Setup

**⚠️ Legacy approach (compatibility issues on Windows):**
```bash
# Traditional setup (may have Windows/path issues)
./start_all.sh <realm-name>
```

### LDAP-Only Setup

**Start LDAP services only (no Keycloak realm setup):**
```bash
./start.sh
```
   
**Note**: On first run, Docker will automatically build the LDAP User Manager image from the included Dockerfile. This may take a few minutes to download dependencies and build the PHP/Apache container.

**Access the services:**
- **LDAP Server Protocol**: `ldap://localhost:389`
- **LDAP Web Manager**: http://localhost:8080
- **Keycloak**: http://localhost:8090

**Login credentials:**
- **LDAP Web Manager (web UI)**: `admin` / `admin`
- **LDAP Server (protocol)**: `cn=admin,dc=min,dc=io` / `admin`
- **Keycloak**: `admin` / `admin`

**Stop everything:**
```bash
./stop.sh
```

## Table of Contents
- [Features](#features)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Container-Based Architecture](#container-based-architecture)
- [Quick Start](#quick-start)
- [Keycloak Integration](#keycloak-integration)
- [Admin-Only Startup](#admin-only-startup)
- [LDAP Configuration](#ldap-configuration)
- [User and Group Management](#user-and-group-management)
- [Web UI Management](#web-ui-management)
- [Keycloak Script Reference](#keycloak-script-reference)
- [Debugging and Troubleshooting](#debugging-and-troubleshooting)
- [Script Reference & Migration](#script-reference--migration)
- [Testing and Verification](#testing-and-verification)
- [LDAP Group Types and Compatibility](#ldap-group-types-and-compatibility)
- [CSV File Structure and Influence](#csv-file-structure-and-influence)
- [Development Notes](#development-notes)
- [Attribution and Credits](#attribution-and-credits)

## Features

- 🔒 **OpenLDAP Server**: Running on Alpine Linux with MDB backend
- 🔐 **Keycloak Identity Provider**: Enterprise-grade identity and access management
- 🐳 **Container-Based Orchestration**: Cross-platform execution eliminating Windows/WSL issues
- 🌟 **Clean Professional Output**: Pre-installed tools with streamlined user experience
- 🌐 **Automatic Network Detection**: Service names in containers, localhost on host
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
├── python-bastion/
│   ├── Dockerfile              # Custom container image with pre-installed tools
│   └── csv_to_ldif.py          # CSV to LDIF conversion script
├── keycloak/                   # Keycloak management scripts
│   ├── create_realm.sh         # Create new Keycloak realms
│   ├── add_ldap_provider_for_keycloak.sh  # Configure LDAP user federation
│   ├── configure_mock_oauth2_idp.sh       # Configure Mock OAuth2 Identity Provider
│   ├── configure_shared_clients.sh        # Create organization-aware shared clients
│   ├── debug_realm_ldap.sh     # Debug realm and LDAP provider status
│   ├── keycloak_details.sh     # Show Keycloak server status and configuration
│   ├── keycloak_setup_full.sh  # Complete Keycloak setup (realm, LDAP, organizations)
│   ├── organization_setup_guide.sh        # Interactive guide for organization features
│   ├── setup_organizations.sh  # Configure organizations with domain mapping
│   ├── sync_ldap.sh            # Synchronize LDAP users and roles with Keycloak
│   └── update_role_mapper.sh   # Update LDAP role mapper configuration
├── ldap/
│   ├── setup_ldap_data.sh      # LDAP container startup script  
│   └── load_additional_users.sh # Load additional users after startup
├── ldap-user-manager/          # Web UI source code (from external repo)
│   ├── Dockerfile
│   ├── www/                    # PHP web application
│   └── ...
├── ldif/                       # Generated LDIF files directory
│   ├── users.ldif              # Generated user and group data
│   ├── admins_only.ldif        # Generated admin-only data
│   └── group_assign.ldif       # Generated group assignments
├── dashboard/
│   └── index.html              # POC dashboard with service links
├── docs/
│   └── WINDOWS_TROUBLESHOOTING.md  # Detailed Windows troubleshooting guide
├── temp/
│   └── log.txt                 # Temporary log files
├── start.sh                    # LDAP-only startup script
├── stop.sh                     # Stop all services script
├── start_all_bastion.sh        # 🚀 RECOMMENDED: Container-based complete setup
├── start_all_bastion_internal.sh # Internal script (runs inside container)
├── start_all.sh                # ⚠️ Legacy: Traditional setup (Windows issues)
├── test_all.sh                 # Verification script for setup
├── test_jwt.sh                 # JWT token testing and validation
├── quick_reference.sh          # Quick reference commands
├── network_detect.sh           # Network detection utility for containers/host
└── README.md                   # This file
```

## Prerequisites

- Docker and Docker Compose
- LDAP client tools (optional, for testing): `brew install openldap` on macOS

## Container-Based Architecture 🐳

This project features a **streamlined container-based orchestration system** that eliminates host platform compatibility issues.

### Enhanced Container-Based Execution

**🚀 Primary Approach: `start_all_bastion.sh`**
- **Cross-Platform Reliability**: Eliminates Windows/WSL/Git Bash path and command issues
- **Clean Professional Output**: No messy package installation feedback - tools are pre-installed
- **Automatic Network Detection**: Uses service names in containers, localhost on host
- **Pre-installed Tools**: docker, curl, jq, ldap-utils ready immediately
- **Consistent Environment**: All operations run in standardized Linux container

### Script Architecture

```
Host System (Windows/macOS/Linux)
├── start_all_bastion.sh        # 🚀 RECOMMENDED: Host wrapper script
│   ├── Starts Docker services
│   ├── Waits for container readiness  
│   └── Executes → start_all_bastion_internal.sh (inside container)
├── start_all.sh                # ⚠️ LEGACY: Traditional host-based (Windows issues)
└── network_detect.sh           # Network detection utility
```

### Benefits of Container-Based Approach

| Feature | Traditional `start_all.sh` | Container-Based `start_all_bastion.sh` |
|---------|----------------------------|----------------------------------------|
| **Windows Support** | ⚠️ Path issues, Git Bash problems | ✅ Works perfectly |
| **Tool Installation** | ⚠️ Messy installation output | ✅ Pre-installed, clean output |
| **Network Detection** | ❌ Manual configuration | ✅ Automatic service name detection |
| **Cross-Platform** | ⚠️ Platform-specific issues | ✅ Identical behavior everywhere |
| **User Experience** | ⚠️ Cluttered feedback | ✅ Professional, streamlined output |

### Windows Support ✅
- **Path Translation Issues**: Eliminated by container execution
- **Git Bash Compatibility**: No longer required - works with any terminal
- **Tool Dependencies**: All tools pre-installed in container image
- **Network Addressing**: Automatic detection handles container vs host context

### Container-Based Operations 🚀

**All operations are now containerized for maximum compatibility!**

**Perfect for:**
- ✅ **Windows users** (eliminates WSL/Git Bash issues)
- ✅ **Cross-platform consistency** (identical behavior everywhere)
- ✅ **Clean user experience** (no messy installation output)
- ✅ **Pre-installed tools** (docker, curl, jq, ldap-utils ready immediately)
- ✅ **Automatic network detection** (service names vs localhost)

### Usage Methods

**🚀 Recommended Container-Based Approach:**

```bash
# Complete LDAP-Keycloak setup (recommended)
./start_all_bastion.sh mycompany --defaults

# Interactive setup with confirmations
./start_all_bastion.sh mycompany --check-steps

# Maintenance operations
./start_all_bastion.sh mycompany --sync-only        # Sync LDAP data only
./start_all_bastion.sh mycompany --load-users       # Load additional users only

# LDAP-only setup (traditional)
./start.sh

# Manual container operations
docker exec python-bastion python python-bastion/csv_to_ldif.py data/admins.csv
docker exec -it python-bastion bash               # Interactive shell
```

### Network Detection Features

The system automatically detects execution context and uses appropriate URLs:

**When running on HOST:**
- Keycloak: `http://localhost:8090`
- LDAP: `ldap://localhost:389`

**When running in CONTAINERS:**
- Keycloak: `http://keycloak:8080` 
- LDAP: `ldap://ldap:389`

### Enhanced User Experience 🌟

The container-based approach delivers a **professional, streamlined experience**:

#### Before (Traditional Approach)
```
⏳ Installing required tools...
📦 Installing curl...
Reading package lists... Done
Building dependency tree... Done
The following NEW packages will be installed:
  curl libcurl4 libcurl3-gnutls libcurl4 libnghttp2-14
✅ Installed: curl
📦 Installing jq...
Reading package lists... Done
[... messy installation output ...]
✅ Installed: jq
```

#### After (Container-Based Approach)
```
🐳 Running from python-bastion container - eliminating host platform issues
🚀 Starting complete LDAP-Keycloak setup for realm: capgemini
🎯 Defaults mode enabled - using default values for all prompts

✅ All required tools available: docker, curl, jq, ldap-utils
🔍 Environment Detection:
   📦 Running inside container - using service names
   🔗 Keycloak: http://keycloak:8080
   🔗 LDAP: ldap://ldap:389
```

#### Key Improvements:
- ✅ **No messy installation output** - tools are pre-installed
- ✅ **Clear environment detection** - shows execution context
- ✅ **Professional progress indicators** - clean, organized feedback
- ✅ **Automatic network resolution** - no manual URL configuration
- ✅ **Consistent experience** - identical output on all platforms

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
# 🚀 Recommended: Complete setup with container-based orchestration
./start_all_bastion.sh company --defaults

# Interactive mode with step-by-step confirmation
./start_all_bastion.sh company --check-steps

# ⚠️ Legacy: Traditional approach (Windows compatibility issues)
./start_all.sh company
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
The `python-bastion/csv_to_ldif.py` script auto-detects based on filename:

**Containerized Method:**
```bash
# Process admin users (auto-detected from filename)
docker exec python-bastion python python-bastion/csv_to_ldif.py data/admins.csv

# Process additional users (auto-detected from filename)
docker exec python-bastion python python-bastion/csv_to_ldif.py data/users.csv

# Show help
docker exec python-bastion python python-bastion/csv_to_ldif.py help
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

## Keycloak Script Reference

The `keycloak/` directory contains specialized scripts for managing Keycloak configuration:

> **🤖 Automation Status:** Scripts marked with ✅ are automatically executed by `start_all_bastion.sh`. Scripts marked with 🔧 are for manual use only.

### Core Setup Scripts

**✅ `keycloak_setup_full.sh <realm-name> [--check-steps] [--defaults]`** *(Master setup script - Auto-executed)*
- Complete Keycloak setup orchestrator called by `start_all_bastion.sh`
- Executes all realm creation, LDAP integration, and organization setup
- Supports interactive (`--check-steps`) and automated (`--defaults`) modes
- Consolidates all Keycloak configuration into a single modular script

**✅ `create_realm.sh <realm-name>`** *(Auto-executed via keycloak_setup_full)*
- Creates a new Keycloak realm with basic configuration
- Sets up realm-specific admin user and role mappings
- Configures default client scopes and protocol mappers

**✅ `add_ldap_provider_for_keycloak.sh <realm-name>`** *(Auto-executed via keycloak_setup_full)*
- Configures LDAP user federation provider in the specified realm
- Sets up connection parameters, search bases, and authentication
- Creates role and group mappers for LDAP synchronization

**✅ `sync_ldap.sh <realm-name>`** *(Auto-executed via keycloak_setup_full)*
- Synchronizes users and roles from LDAP to Keycloak
- Triggers full user import and role mapping updates
- Provides detailed status reporting and error handling

### Organization & Advanced Features

**✅ `setup_organizations.sh <realm-name> [org-prefixes...]`** *(Auto-executed via keycloak_setup_full)*
- Configures Keycloak Organizations feature (requires Keycloak 26+)
- Creates organizations with domain mapping (e.g., `acme.realm.local`)
- Sets up organization-specific role filtering and management

**✅ `configure_shared_clients.sh <realm-name> [org-prefixes...]`** *(Auto-executed via keycloak_setup_full)*
- Creates shared clients with organization-aware role filtering
- Configures protocol mappers for organization detection in JWT tokens
- Sets up client scopes for multi-organization support

**✅ `configure_mock_oauth2_idp.sh <realm-name> [org-prefixes...]`** *(Auto-executed via keycloak_setup_full)*
- Configures Mock OAuth2 server as external Identity Provider
- Creates organization-specific OAuth2 clients and mappers
- Enables multi-provider authentication testing scenarios

### Debugging & Maintenance

**🔧 `debug_realm_ldap.sh <realm-name>`** *(Manual use only)*
- Simple diagnostics for realm and LDAP provider status
- Tests basic connectivity and displays provider information
- Useful for manual troubleshooting (not called by automated scripts)

**✅ `keycloak_details.sh`** *(Auto-executed via keycloak_setup_full for status checks)*
- Shows Keycloak server status, version, and configuration
- Lists all realms and their basic properties
- Displays enabled features and extension information

**🔧 `organization_setup_guide.sh`** *(Interactive guide only)*
- Displays organization setup concepts and step-by-step instructions
- Educational resource for understanding organization features
- Not executed automatically - run manually for guidance

### Mapper Configuration

**✅ `update_role_mapper.sh <realm-name>`** *(Auto-executed via keycloak_setup_full)*
- Updates LDAP role mapper configuration and filters
- Modifies role synchronization patterns and group mappings
- Useful for adjusting which LDAP groups sync as Keycloak roles

### Usage Examples

```bash
# Complete Keycloak setup (recommended - used by start_all_bastion.sh)
./keycloak/keycloak_setup_full.sh mycompany                    # Interactive mode
./keycloak/keycloak_setup_full.sh mycompany --defaults         # Automated mode
./keycloak/keycloak_setup_full.sh mycompany --check-steps      # Step-by-step confirmation

# Individual component setup (manual/advanced usage)
./keycloak/create_realm.sh mycompany
./keycloak/add_ldap_provider_for_keycloak.sh mycompany
./keycloak/sync_ldap.sh mycompany

# Organization-specific setup (manual/advanced usage)
./keycloak/setup_organizations.sh mycompany acme xyz
./keycloak/configure_shared_clients.sh mycompany acme xyz
./keycloak/configure_mock_oauth2_idp.sh mycompany acme xyz

# Debugging and maintenance
./keycloak/debug_realm_ldap.sh mycompany
./keycloak/keycloak_details.sh
./keycloak/organization_setup_guide.sh
```

### Script Organization Summary

- **🤖 Master Script (1):** `keycloak_setup_full.sh` - Complete setup orchestrator called by `start_all_bastion.sh`
- **⚙️ Component Scripts (8):** Individual Keycloak configuration components executed by master script
- **🔧 Manual Tools (2):** Troubleshooting and interactive guidance utilities
- **📁 Total:** 11 focused, functional scripts with clear modular architecture

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
docker exec python-bastion python python-bastion/csv_to_ldif.py

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

If you need `groupOfNames` instead (uses full DN membership), modify `python-bastion/csv_to_ldif.py`:

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
# From python-bastion/csv_to_ldif.py
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

To change the LDAP structure, edit `python-bastion/csv_to_ldif.py`:

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
   - Runs `python-bastion/csv_to_ldif.py` to convert CSV to LDIF
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

## Script Reference & Migration

### Primary Scripts (User-Facing)

**🚀 RECOMMENDED: Container-Based Scripts**
- `start_all_bastion.sh` - Complete LDAP-Keycloak setup (cross-platform)
- `start.sh` - LDAP-only setup
- `stop.sh` - Stop all services
- `test_all.sh` - Testing and verification
- `test_jwt.sh` - JWT token validation

**⚠️ LEGACY: Traditional Scripts**
- `start_all.sh` - Traditional setup (Windows compatibility issues)

**🔧 INTERNAL: Container-Only Scripts**
- `start_all_bastion_internal.sh` - Internal script (runs inside container - users never call directly)
- `network_detect.sh` - Network detection utility (sourced by other scripts)

### Migration Guide

**From Legacy to Container-Based:**
```bash
# Old approach (Windows issues)
./start_all.sh myrealm

# New approach (recommended)
./start_all_bastion.sh myrealm --defaults
```

### Auxiliary Documentation Files

The following auxiliary markdown files have been **consolidated into this README**:
- ✅ `CONTAINER_EXECUTION.md` - Container usage information (integrated above)
- ✅ `CONTAINER_NETWORK_GUIDE.md` - Network detection guide (integrated above) 
- ✅ `NETWORK_IMPROVEMENTS_SUMMARY.md` - Enhancement summary (integrated above)
- ⚠️ `WINDOWS_TROUBLESHOOTING.md` - **Keep for Windows-specific issues**

**Recommendation:** The first three files can be removed as their content is now in the main README. Keep `WINDOWS_TROUBLESHOOTING.md` for detailed Windows-specific troubleshooting.

## Testing and Verification

### JWT Token Verification

The `test_jwt.sh` script validates JWT tokens and role assignments:

```bash
# Test specific users with custom realm
./test_jwt.sh capgemini test-acme-admin test-xyz-user alice

# Use defaults flag to test with organization test users
./test_jwt.sh capgemini --defaults

# Or with --defaults first for default realm (uses capgemini)
./test_jwt.sh --defaults

# Works with any realm name
./test_jwt.sh myrealm test-acme-admin test-xyz-user
```

**Features:**
- 🔄 **CSV Password Support**: Automatically reads passwords from `data/users.csv`
- 🎯 **Flexible Users**: Test any combination of users (CSV or non-CSV)
- 🏢 **Realm Agnostic**: Works with any Keycloak realm name
- 🔍 **JWT Decoding**: Base64 decodes and displays token contents
- ✅ **Role Validation**: Shows assigned roles for each user

### Complete Integration Testing

Run the full test suite:

```bash
# Test all components with specific realm
./test_all.sh capgemini

# Test with default realm
./test_all.sh
```

## License

This POC project configuration is provided as-is for educational and development purposes. Please respect the licenses of the included components:
- LDAP User Manager: MIT License
- OpenLDAP: OpenLDAP Public License
- Alpine Linux: Various open source licenses
