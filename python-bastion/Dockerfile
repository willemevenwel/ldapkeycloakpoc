# Python utilities container with pre-installed tools for cross-platform script execution
FROM python:3.11-slim

# Install system dependencies and tools in a single layer for efficiency
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        # Core networking and container tools
        curl \
        jq \
        # LDAP utilities for LDAP operations
        ldap-utils \
        # Additional utilities
        git \
        wget \
        # Clean up to reduce image size
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    # Install Docker CLI client binary (static binary)
    && DOCKER_VERSION="24.0.7" \
    && wget -O /tmp/docker.tgz "https://download.docker.com/linux/static/stable/$(uname -m)/docker-${DOCKER_VERSION}.tgz" \
    && tar -xzf /tmp/docker.tgz -C /tmp \
    && mv /tmp/docker/docker /usr/local/bin/docker \
    && chmod +x /usr/local/bin/docker \
    && rm -rf /tmp/docker*

# Set working directory
WORKDIR /workspace

# Set environment variables
ENV PYTHONPATH=/workspace
ENV PYTHONUNBUFFERED=1

# Keep container running
CMD ["tail", "-f", "/dev/null"]