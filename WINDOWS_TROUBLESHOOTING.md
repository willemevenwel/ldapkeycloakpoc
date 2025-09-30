# Windows Troubleshooting Guide for LDAP-Keycloak POC

## Common Windows Issues and Solutions

### 1. LDAP Authentication Fails (Error 49: Invalid Credentials)

**Symptoms:**
- `ldap_bind: Invalid credentials (49)` error
- Works on macOS but fails on Windows
- LDAP container starts but authentication fails

**Causes:**
- Windows Docker initialization timing differences
- File path case sensitivity issues
- Container networking differences

**Solutions:**

#### Quick Fix:
```bash
# Run the enhanced test script with debug mode first
./test_all.sh your-realm-name --debug

# If setup is still failing, try regenerating and reloading data
docker exec python-bastion python python/csv_to_ldif.py data/admins.csv
./ldap/setup_ldap_data.sh
```

#### Full Reset:
```bash
# Stop all services
docker-compose down -v

# Remove volumes (this will delete all data)
docker volume prune -f

# Restart everything
./start_all.sh your-realm-name
```

### 2. Container Startup Issues

**Symptoms:**
- Containers fail to start
- "Port already in use" errors
- Services don't respond

**Solutions:**

#### Check Docker Desktop:
1. Ensure Docker Desktop is running
2. Switch to Linux containers (not Windows containers)
3. Increase memory allocation to 4GB+ in Docker Desktop settings
4. Restart Docker Desktop

#### Port Conflicts:
```bash
# Check what's using the ports
netstat -ano | findstr :389
netstat -ano | findstr :8090
netstat -ano | findstr :8080

# Kill processes if needed (run as administrator)
taskkill /PID <process_id> /F
```

### 3. File Path Issues

**Symptoms:**
- Scripts can't find files
- Permission denied errors
- CSV/LDIF files not found

**Solutions:**

#### Use Full Paths:
```bash
# Instead of relative paths, use full paths
cd C:\path\to\ldapkeycloakpoc
./start_all.sh realm-name
```

#### Check File Permissions:
```bash
# Ensure scripts are executable
chmod +x *.sh
chmod +x ldap/*.sh
chmod +x keycloak/*.sh
```

### 4. PowerShell vs Command Prompt

**Issue:** Scripts written for bash may not work in PowerShell

**Solutions:**

#### Use Git Bash (Recommended):
1. Install Git for Windows
2. Use Git Bash instead of PowerShell
3. Run scripts in Git Bash terminal

#### Use WSL (Windows Subsystem for Linux):
1. Install WSL2
2. Install Ubuntu or similar
3. Run Docker Desktop with WSL2 backend
4. Run scripts from WSL terminal

### 5. Docker Volume Issues

**Symptoms:**
- Data not persisting
- Permission errors in containers
- Volumes not mounting correctly

**Solutions:**

#### Reset Volumes:
```bash
# Stop containers
docker-compose down

# Remove volumes
docker volume rm ldapkeycloakpoc_ldap_data ldapkeycloakpoc_ldap_config

# Restart
docker-compose up -d
```

#### Check Volume Mounts:
```bash
# Inspect volume mounts
docker inspect ldap | grep -A 10 '"Mounts"'
```

### 6. Network Connectivity Issues

**Symptoms:**
- Services can't communicate
- "Connection refused" errors
- DNS resolution failures

**Solutions:**

#### Check Docker Network:
```bash
# List networks
docker network ls

# Inspect default network
docker network inspect ldapkeycloakpoc_default
```

#### Test Connectivity:
```bash
# Test from keycloak to ldap
docker exec keycloak ping ldap

# Test from host to containers
curl http://localhost:8090
curl -I http://localhost:389  # Should connection refuse (expected for HTTP on LDAP port)
```

### 7. Performance Issues

**Symptoms:**
- Very slow container startup
- Services timeout during initialization
- High CPU/memory usage

**Solutions:**

#### Increase Docker Resources:
1. Open Docker Desktop
2. Go to Settings → Resources
3. Increase:
   - Memory to 4GB+
   - CPU to 2+ cores
   - Disk image size if needed

#### Use SSD Storage:
- Move Docker data to SSD if using HDD
- Consider moving entire project to SSD

### 8. Script Execution Issues

**Symptoms:**
- "Permission denied" when running scripts
- Scripts not found
- Line ending errors

**Solutions:**

#### Fix Line Endings:
```bash
# Convert Windows line endings to Unix
dos2unix *.sh
dos2unix ldap/*.sh
dos2unix keycloak/*.sh
```

#### Set Execute Permissions:
```bash
find . -name "*.sh" -exec chmod +x {} \;
```

## Windows-Specific Best Practices

### 1. Environment Setup
- Use Git Bash or WSL2 for shell operations
- Ensure Docker Desktop uses Linux containers
- Allocate sufficient resources to Docker

### 2. Development Workflow
- Always use the debug script when issues occur
- Check service readiness before proceeding
- Use full paths when possible

### 3. Troubleshooting Order
1. Run `./debug_ldap_connectivity.sh`
2. Check Docker Desktop status and logs
3. Verify port availability
4. Test with full container restart
5. Check file permissions and line endings

### 4. Emergency Reset Commands
```bash
# Nuclear option - reset everything
docker-compose down -v
docker system prune -f
docker volume prune -f
./start_all.sh your-realm-name
```

## Getting Help

If issues persist:

1. Run the enhanced test script with debug mode and save output:
   ```bash
   ./test_all.sh your-realm-name --debug > debug_output.txt 2>&1
   ```

2. Check container logs:
   ```bash
   docker logs ldap > ldap_logs.txt 2>&1
   docker logs keycloak > keycloak_logs.txt 2>&1
   ```

3. Check system information:
   ```bash
   docker version
   docker-compose version
   systeminfo | findstr /B /C:"OS Name" /C:"OS Version"
   ```