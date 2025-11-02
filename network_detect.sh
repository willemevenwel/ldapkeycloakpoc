#!/bin/bash

# Network detection utility for LDAP-Keycloak POC
# Detects if running inside container or on host and provides appropriate URLs

# Function to detect if we're running inside a container
is_running_in_container() {
    # Check multiple indicators that we're in a container
    if [ -f /.dockerenv ]; then
        return 0  # We're in a container
    fi
    
    # Check if we can see container-style cgroup
    if [ -f /proc/1/cgroup ] && grep -q "docker\|containerd" /proc/1/cgroup 2>/dev/null; then
        return 0  # We're in a container
    fi
    
    # Check if hostname matches common container patterns
    if [ "$(hostname)" != "$(hostname -f)" ] && [ "$(hostname)" != "localhost" ]; then
        # Additional check: can we resolve container service names?
        if nslookup keycloak >/dev/null 2>&1 || getent hosts keycloak >/dev/null 2>&1; then
            return 0  # We're in a container with service discovery
        fi
    fi
    
    return 1  # We're on the host
}

# Function to get Keycloak URL based on environment
get_keycloak_url() {
    if is_running_in_container; then
        echo "http://keycloak:8080"
    else
        echo "http://localhost:8090"
    fi
}

# Function to get LDAP URL for client connections (scripts connecting TO LDAP)
get_ldap_url() {
    if is_running_in_container; then
        echo "ldap://ldap:389"
    else
        echo "ldap://localhost:389"
    fi
}

# Function to get LDAP URL for Keycloak configuration
# Keycloak always runs in a container, so it always needs the container network name
get_ldap_url_for_keycloak() {
    echo "ldap://ldap:389"
}

# Function to get Mock OAuth2 URL for client connections (scripts connecting TO Mock OAuth2)
get_mock_oauth2_url() {
    if is_running_in_container; then
        echo "http://mock-oauth2-server:8080"
    else
        echo "http://localhost:8081"
    fi
}

# Function to get Mock OAuth2 URL for Keycloak IdP configuration
# Keycloak always runs in a container, so it always needs the container network name
get_mock_oauth2_url_for_keycloak() {
    echo "http://mock-oauth2-server:8080"
}

# Function to get LDAP Web Manager URL based on environment
get_ldap_manager_url() {
    if is_running_in_container; then
        echo "http://ldap-manager:80"
    else
        echo "http://localhost:8080"
    fi
}

# Function to display current environment detection
show_environment_info() {
    echo "🔍 Environment Detection:"
    if is_running_in_container; then
        echo "   📦 Running inside container - using service names"
        echo "   🔗 Keycloak: $(get_keycloak_url)"
        echo "   🔗 LDAP: $(get_ldap_url)"
        echo "   🔗 Mock OAuth2: $(get_mock_oauth2_url)"
    else
        echo "   🖥️  Running on host - using localhost"
        echo "   🔗 Keycloak: $(get_keycloak_url)"
        echo "   🔗 LDAP: $(get_ldap_url)"
        echo "   🔗 Mock OAuth2: $(get_mock_oauth2_url)"
    fi
}

# Export functions for use in other scripts
export -f is_running_in_container
export -f get_keycloak_url
export -f get_ldap_url
export -f get_ldap_url_for_keycloak
export -f get_mock_oauth2_url
export -f get_mock_oauth2_url_for_keycloak
export -f get_ldap_manager_url
export -f show_environment_info