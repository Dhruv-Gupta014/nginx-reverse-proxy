#!/usr/bin/env bash
# =============================================================================
# setup.sh — Discovers actual network names and starts the Nginx reverse proxy
# Run this AFTER Chatwoot and Superset are both up and running.
# =============================================================================
set -e

echo "==========================================="
echo " Discovering Docker networks"
echo "==========================================="
docker network ls

echo ""
echo "==========================================="
echo " Discovering running containers"
echo "==========================================="
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}"

echo ""
echo "==========================================="
echo " Inspecting Chatwoot network"
echo "==========================================="
CHATWOOT_NET=$(docker network ls --format "{{.Name}}" | grep -i chatwoot | head -1)
echo "Detected: $CHATWOOT_NET"
docker network inspect "$CHATWOOT_NET" --format '{{range .Containers}}{{.Name}} -> {{.IPv4Address}}{{println}}{{end}}'

echo ""
echo "==========================================="
echo " Inspecting Superset network"
echo "==========================================="
SUPERSET_NET=$(docker network ls --format "{{.Name}}" | grep -i superset | head -1)
echo "Detected: $SUPERSET_NET"
docker network inspect "$SUPERSET_NET" --format '{{range .Containers}}{{.Name}} -> {{.IPv4Address}}{{println}}{{end}}'

echo ""
echo "==========================================="
echo " IMPORTANT: Update docker-compose.yml"
echo "==========================================="
echo "Set these in docker-compose.yml under 'networks:':"
echo "  chatwoot_network -> name: $CHATWOOT_NET"
echo "  superset_network -> name: $SUPERSET_NET"
echo ""
echo "Then also update nginx/nginx.conf upstream blocks with the"
echo "exact container names shown above (not image names)."
echo ""
read -p "Press Enter once you've verified/updated the names to continue..."

echo ""
echo "==========================================="
echo " Starting Nginx reverse proxy"
echo "==========================================="
docker compose up -d

echo ""
echo "==========================================="
echo " Verifying"
echo "==========================================="
sleep 3
docker ps | grep nginx
echo ""
echo "Test these URLs:"
echo "  http://localhost/nginx-health"
echo "  http://localhost/chatwoot/"
echo "  http://localhost/superset/"
