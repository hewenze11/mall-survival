# Mall Survival Server (M1)

Colyseus game server for the **Mall Survival** multiplayer game.

## Tech Stack

- **Runtime**: Node.js 20
- **Framework**: Colyseus 0.16 (multiplayer game server)
- **Schema**: @colyseus/schema v2
- **Language**: TypeScript

## Architecture

```
src/
├── index.ts              # Server entry point (port 2567)
├── rooms/
│   └── GameRoom.ts       # Main game room (player join/leave, game loop)
├── schemas/
│   ├── GameState.ts      # Game state (phase, wave, players, zombies)
│   ├── Player.ts         # Player schema (position, health, hunger)
│   └── Zombie.ts         # Zombie schema (position, health, target)
├── systems/
│   ├── WaveSystem.ts     # Wave scheduler (prep → wave → next wave)
│   └── FloorSystem.ts    # Floor/scene system (M3 skeleton)
└── config/
    └── ConfigLoader.ts   # Reads ../config/*.json
```

## Game State Machine

```
WAITING → PREP (5min) → WAVE → (next wave or) ENDED
```

- **WAITING**: No players yet
- **PREP**: 5-minute countdown before first wave
- **WAVE**: Zombies spawning and attacking
- **ENDED**: All waves cleared or all players dead

## API Endpoints

### HTTP
| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |
| `/info` | GET | Server info |
| `/matchmake/joinOrCreate/game` | POST | Join or create game room |

### WebSocket Messages (Client → Server)
| Message | Payload | Description |
|---------|---------|-------------|
| `move` | `{x, y, direction}` | Player movement |
| `shoot` | `{targetX, targetY}` | Player shoot action |
| `ready` | - | Player ready signal |

### WebSocket Messages (Server → Client)
Colyseus automatically syncs `GameState` schema changes via delta encoding.

## Quick Start

```bash
# Install dependencies
npm install

# Development (with hot reload)
npm run dev:watch

# Build
npm run build

# Production
npm start
```

## Configuration

Game parameters are in `../config/`:

- **entities.json**: Player/zombie stats (health, speed, hunger)
- **waves.json**: Wave configs (zombie count, spawn interval, prep time)

## Docker

```bash
docker build -t mall-survival-server .
docker run -p 2567:2567 mall-survival-server
```

## M3 Preview (Floor System)

`FloorSystem.migrateEntity(entityId, fromFloor, toFloor)` is stubbed and ready for M3 implementation, which will include:
- Cross-floor zombie tracking
- Floor load/unload events
- Client-side floor transitions
