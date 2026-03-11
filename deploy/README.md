# Deployment Guide

## Infrastructure
- **ip1** (104.64.211.23): Game server - runs mall-survival-server
- **ip2** (104.64.211.27): Private Docker registry (port 5000)
- **ip3** (104.64.211.32): Monitoring (Prometheus/Grafana)

## Deployment Files on ip1
- `/opt/game/docker-compose.game.yml` - Docker Compose config for game server
- `/opt/game/update.sh` - Manual update script (pull latest image + restart)

## CI/CD Flow
1. Push to `main` branch with changes in `server/` → triggers **Server Deploy** workflow
2. GitHub Actions runner:
   - Configures insecure registry for ip2:5000
   - Builds Docker image from `server/Dockerfile`
   - Pushes to `104.64.211.27:5000/mall-survival-server:latest`
3. SSH into ip1, pulls new image, restarts via docker-compose

## Manual Update
```bash
ssh root@104.64.211.23
/opt/game/update.sh
```

## Rollback
```bash
ssh root@104.64.211.23
docker pull 104.64.211.27:5000/mall-survival-server:<commit-sha>
docker-compose -f /opt/game/docker-compose.game.yml up -d --force-recreate
```
