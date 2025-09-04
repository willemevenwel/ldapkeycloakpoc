#!/bin/sh

echo "Stopping all services and removing containers (keeping images and volumes)..."
docker-compose down --remove-orphans

echo "All services have been stopped and containers removed."
echo "LDAP server is now offline."
