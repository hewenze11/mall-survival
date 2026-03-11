#!/bin/bash
set -e

COMPOSE_FILE="/opt/game/docker-compose.game.yml"

echo "[$(date)] Starting rolling update..."
docker-compose -f "$COMPOSE_FILE" pull
docker-compose -f "$COMPOSE_FILE" up -d
echo "[$(date)] Rolling update complete."
