# Group Types: groupOfNames and posixGroup

This project generates both `groupOfNames` and `posixGroup` entries for every group in LDAP:

- **groupOfNames**: Standard LDAP group, uses the `member` attribute (full DNs). Useful for general LDAP tools and access control.
- **posixGroup**: Used for Unix/Linux integration and required by some LDAP UIs (like Wheelybird). Uses the `memberUid` attribute (usernames).

**Why both?**

Creating both group types ensures compatibility with:
- General LDAP tools and access control (which expect `groupOfNames`)
- Unix/Linux systems and UIs (which expect `posixGroup`)

This is a common best practice for environments that use both LDAP and Unix/Linux tools or web UIs.
# LDAP Container POC

A lightweight Docker Compose setup for OpenLDAP with automated CSV to LDIF conversion and import.

## Features

- 🔒 OpenLDAP server running on Alpine Linux
- 📊 Automated CSV to LDIF conversion and import
- 🔄 Automatic user/group import on container startup
- 🔐 SHA-hashed password support
- 📁 Organized directory structure with OUs for users and groups
- 🚀 Minimal setup - only LDAP server, no unnecessary web interfaces

## Project Structure

```
ldapkeycloakpoc/
├── docker-compose.yml          # Main Docker Compose configuration
├── users.csv                   # User and group data source
├── csv_to_ldif.py              # CSV to LDIF conversion script
├── start_ldap.sh               # LDAP container startup script
├── start.sh                    # Main startup script
├── stop.sh                     # Stop all services script
├── ldif/                       # Generated LDIF files directory
└── README.md                   # This file
```

## Prerequisites

- Docker
- Docker Compose
- LDAP client tools (for testing) - `brew install openldap` on macOS

## Quick Start

1. **Start the entire LDAP ecosystem:**
   ```bash
   ./start.sh
   ```
   
   This automatically:
   - Creates necessary directories
   - Starts Docker Compose services
   - Installs OpenLDAP and Python in container
   - Converts CSV to LDIF format
   - Starts LDAP server
   - Imports all users and groups
   - Displays connection information

2. **Access the LDAP server:**
   - **LDAP Server:** `ldap://localhost:389`

3. **Stop everything:**
   ```bash
   ./stop.sh
   ```

## Configuration

### LDAP Server Details

- **Domain:** `mycompany.local`
- **Base DN:** `dc=mycompany,dc=local`
- **Admin DN:** `cn=admin,dc=mycompany,dc=local`
- **Admin Password:** `admin`
- **Users OU:** `ou=users,dc=mycompany,dc=local`
- **Groups OU:** `ou=groups,dc=mycompany,dc=local`

## User Management

### CSV Format

Edit `users.csv` to manage users:
```csv
username,firstname,lastname,email,password,groups
alice,Alice,Smith,alice@mycompany.local,alice123,developers
bob,Bob,Johnson,bob@mycompany.local,bob123,admins
charlie,Charlie,Brown,charlie@mycompany.local,charlie123,developers;admins
```

**Field Descriptions:**
- `username`: Unique identifier (becomes uid in LDAP)
- `firstname`: User's given name
- `lastname`: User's surname
- `email`: Email address
- `password`: Plain text password (automatically SHA-hashed)
- `groups`: Semicolon-separated group list

### Applying Changes

To update users after editing CSV:
```bash
./stop.sh
./start.sh
```

### Manual Data Loading

If you want to work with the CSV conversion independently:

```bash
# 1. Generate LDIF from CSV manually
python3 csv_to_ldif.py

# 2. Check the generated LDIF
cat ldif/users.ldif

# 3. Start LDAP server (if not running)
./start.sh

# 4. Wait for server to be ready, then import manually
sleep 10
ldapadd -x -H ldap://localhost:389 -D "cn=admin,dc=mycompany,dc=local" -w admin -f ldif/users.ldif
```

**When to use manual loading:**
- Testing LDIF generation without restarting containers
- Debugging CSV format issues
- Custom import scenarios
- Learning how the conversion works

## Commands Reference

### Basic Operations
```bash
# Start everything (import + start services)
./start.sh

# Stop everything
./stop.sh
```

### Docker Operations
```bash
# View running containers
docker ps

# View all containers (including stopped)
docker ps -a

# View logs from LDAP container
docker logs my-openldap

# Follow logs in real-time
docker logs -f my-openldap

# Get latest log entries
docker logs my-openldap --tail 20
```

### LDAP Testing Commands
```bash
# Search all entries
ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=mycompany,dc=local" -w admin -b "dc=mycompany,dc=local" "(objectClass=*)"

# Search for users only
ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=mycompany,dc=local" -w admin -b "ou=users,dc=mycompany,dc=local" "(objectClass=inetOrgPerson)"

# Search for groups only
ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=mycompany,dc=local" -w admin -b "ou=groups,dc=mycompany,dc=local" "(objectClass=groupOfNames)"

# Test specific user
ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=mycompany,dc=local" -w admin -b "dc=mycompany,dc=local" "(uid=alice)"
```

## Troubleshooting

### Container Issues
```bash
# Check container status
docker ps -a

# View container logs
docker logs my-openldap

# Get into container for debugging
docker exec -it my-openldap /bin/sh

# Check LDAP server process
docker exec my-openldap ps aux | grep slapd
```

### LDAP Connection Issues
```bash
# Test LDAP connection
ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=mycompany,dc=local" -w admin -s base

# Check if LDAP port is accessible
telnet localhost 389

# Check what's listening on port 389
lsof -i :389
```

### Import Issues
```bash
# Check generated LDIF file
cat ldif/users.ldif

# Manually run CSV conversion (requires Python 3)
python3 csv_to_ldif.py

# Check if LDIF was generated correctly
ls -la ldif/users.ldif

# Test manual import to LDAP
ldapadd -x -H ldap://localhost:389 -D "cn=admin,dc=mycompany,dc=local" -w admin -f ldif/users.ldif

# Clear LDAP and re-import (if needed)
./stop.sh
rm ldif/users.ldif
./start.sh
```

### Manual CSV to LDIF Conversion

If you want to generate the LDIF file manually without starting the container:

```bash
# Make sure you have Python 3 installed
python3 --version

# Run the conversion script
python3 csv_to_ldif.py

# Check the generated file
cat ldif/users.ldif

# The script reads from users.csv and writes to ldif/users.ldif
```

**Note:** The Python script expects:
- `users.csv` to exist in the current directory
- `ldif/` directory to exist (will be created if missing)
- Python 3 with standard libraries (csv, hashlib, base64)

### File Issues
```bash
# Check file permissions
ls -la *.sh

# Make scripts executable if needed
chmod +x start.sh stop.sh

# Check CSV format and structure
head -5 users.csv

# Validate CSV has proper headers
head -1 users.csv
head -5 users.csv
```

## How It Works

### Startup Sequence
1. `start.sh` calls `docker-compose up -d`
2. Docker starts `my-openldap` container with Alpine Linux
3. Container runs `start_ldap.sh` which:
   - Installs OpenLDAP, Python, and dependencies
   - Creates LDAP configuration with MDB backend
   - Runs `csv_to_ldif.py` to convert CSV to LDIF
   - Starts LDAP server
   - Imports the generated LDIF file
   - Keeps LDAP server running

### Generated LDIF Structure
```ldif
# Base domain
dn: dc=mycompany,dc=local
objectClass: dcObject
objectClass: organization

# Organizational Units
dn: ou=users,dc=mycompany,dc=local
dn: ou=groups,dc=mycompany,dc=local

# Users
dn: uid=alice,ou=users,dc=mycompany,dc=local
objectClass: inetOrgPerson
cn: Alice Smith
# ... other attributes

# Groups
dn: cn=developers,ou=groups,dc=mycompany,dc=local
objectClass: groupOfNames
member: uid=alice,ou=users,dc=mycompany,dc=local
# ... other members
```

## Security Notes

⚠️ **This is a development/testing setup:**
- Default passwords are used
- No SSL/TLS encryption
- No access controls beyond basic authentication
- Suitable for POC and development only

For production use:
- Change all default passwords
- Implement LDAPS (LDAP over SSL)
- Add proper access controls and authentication
- Use Docker secrets for sensitive data
- Implement backup strategies

## Common Issues and Solutions

### "Container Exits Immediately"
- Check logs: `docker logs my-openldap`
- Usually indicates script error in `start_ldap.sh`

### "Can't Contact LDAP Server"
- Container may still be starting (wait 30-60 seconds)
- Check if container is running: `docker ps`
- Check logs for errors

### "No Such Object" Error During Import
- Base domain may not be created
- Check LDIF file includes base domain entry

### "Permission Denied" on Scripts
- Run: `chmod +x start.sh stop.sh`

## Development Notes

This setup was evolved through several iterations:
1. Started with basic Alpine + OpenLDAP
2. Fixed MDB backend loading issues
3. Added base domain creation to LDIF
4. Separated startup logic into dedicated script
5. Removed problematic docker-compose override file

The key breakthrough was using `moduleload back_mdb` in the LDAP configuration and ensuring the base domain is created before organizational units.
