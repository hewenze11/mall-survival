# 大楼求生 (Mall Survival)

A multiplayer survival game built with Godot (client) and Colyseus (server).

## Project Structure

```
mall-survival/
├── client/          # Godot 4.2 client
├── server/          # Colyseus game server
├── config/          # Game balance configuration
│   ├── entities.json    # Player and zombie stats
│   └── waves.json       # Wave configuration
├── deploy/          # Deployment scripts
│   ├── docker-compose.game.yml
│   └── update.sh
└── .github/workflows/   # CI/CD pipelines
    ├── server-deploy.yml
    └── client-build.yml
```

## Infrastructure

| Component | Host | Address |
|-----------|------|---------|
| Game Server | ip1 | 104.64.211.23:2567 |
| Private Registry | ip2 | 104.64.211.27:5000 |
| Monitoring | ip3 | 104.64.211.32:3000 / :9090 |

## Development

### Server
The game server is built with [Colyseus](https://colyseus.io/), a multiplayer framework for Node.js.

### Client
The client is built with [Godot 4.2](https://godotengine.org/).

## Deployment

Pushes to `main` automatically trigger CI/CD:
- Changes in `server/` → build Docker image → push to private registry → rolling update on ip1
- Changes in `client/` → build Windows & Linux exports → upload as artifacts

## Configuration

- `config/entities.json`: Player and zombie base stats
- `config/waves.json`: Wave timing and zombie counts

## Milestones

- [x] **M0**: Infrastructure setup
- [ ] **M1**: Server-side game logic (Colyseus rooms, state sync)
- [ ] **M2**: Client-side game (Godot scenes, networking)
