# Mall Survival - 客户端 (Client)

《大楼求生》是一款 2D 俯视角多人在线生存游戏，使用 Godot 4.2 开发。

## 项目简介

- **引擎**：Godot 4.2 (GDScript)
- **视角**：2D 俯视角（Top-down）
- **类型**：多人在线生存游戏
- **阶段**：M2 - 客户端骨架

### 游戏概述

玩家被困在一栋商场中，需要合作抵抗一波波涌入的僵尸。
每层楼都有独特的挑战，玩家需要搜集物资、制作武器、守住据点。

## 快速开始

### 环境要求

- Godot 4.2.x（[下载地址](https://godotengine.org/download)）
- 运行中的 Colyseus 服务端（或使用公共测试服）

### 在本地运行

1. 克隆仓库：
   ```bash
   git clone https://github.com/hewenze11/mall-survival.git
   cd mall-survival
   ```

2. 用 Godot 4.2 打开项目：
   - 打开 Godot 编辑器
   - 点击 "Import" 或 "导入"
   - 选择 `client/project.godot`
   - 点击 "Import & Edit"

3. 运行项目：
   - 按 F5 或点击编辑器右上角的播放按钮
   - 在主菜单输入玩家名，点击"加入游戏"

### 修改服务器地址

如需连接不同的服务器，修改 `scripts/MainMenu.gd` 中的服务器地址：
```gdscript
NetworkManager.connect_to_server(
    "ws://YOUR_SERVER:2567",  # 修改这里
    "game",
    player_name
)
```

## 项目结构

```
client/
├── project.godot              # Godot 4.2 项目配置文件
├── export_presets.cfg         # 导出预设（Windows + Linux）
├── scenes/
│   ├── MainMenu.tscn          # 主菜单场景（玩家名输入、加入游戏）
│   ├── Game.tscn              # 主游戏场景（1楼地图、HUD）
│   └── Player.tscn            # 玩家节点场景（共用于本地和远程玩家）
├── scripts/
│   ├── MainMenu.gd            # 主菜单逻辑
│   ├── Game.gd                # 游戏主逻辑（状态同步、玩家管理）
│   ├── Player.gd              # 本地玩家控制（WASD + 鼠标）
│   ├── RemotePlayer.gd        # 远程玩家（位置插值）
│   ├── NetworkManager.gd      # 网络管理单例（WebSocket + Colyseus）
│   └── HUD.gd                 # HUD 界面（血量、饥饿、波次、倒计时）
└── assets/
    └── placeholder/           # 占位资源说明（M2阶段无外部资源）
```

## 网络架构

### 概述

```
[Godot Client]
      │
      │  WebSocket (JSON)
      │  ws://104.64.211.23:2567/game
      ▼
[Colyseus Server]
      │
      │  Room State (state machine)
      ▼
[Game Room: "game"]
  - 玩家状态 (位置, 血量, 饥饿)
  - 波次系统
  - 僵尸 AI
```

### 通信协议

使用简化的 JSON 协议（基于 Colyseus 消息格式）：

**客户端 → 服务端消息：**

| 消息类型 | 字段 | 说明 |
|---------|------|------|
| `join`  | `playerName` | 加入游戏房间 |
| `move`  | `x, y, direction` | 玩家移动（50ms 节流） |
| `shoot` | `targetX, targetY` | 玩家射击 |
| `interact` | - | 与环境交互 |

**服务端 → 客户端消息：**

| 消息类型 | 字段 | 说明 |
|---------|------|------|
| `joined` | `sessionId, state` | 加入成功 |
| `state`  | `players, wave, phase, countdown` | 完整状态快照 |
| `patch`  | 部分状态 | 增量状态更新 |
| `playerJoined` | `id, player` | 新玩家加入 |
| `playerLeft` | `id` | 玩家离线 |
| `phase` | `phase, countdown` | 游戏阶段变化 |
| `damage` | `amount` | 玩家受伤 |

### NetworkManager 单例

`NetworkManager` 作为 Godot Autoload 单例全局可用，提供：

```gdscript
# 连接服务器
NetworkManager.connect_to_server(url, room_name, player_name)

# 发送消息
NetworkManager.send_move(x, y, direction)
NetworkManager.send_shoot(target_x, target_y)

# 信号
NetworkManager.connected           # 连接成功
NetworkManager.disconnected        # 连接断开
NetworkManager.state_updated(state)    # 状态更新
NetworkManager.player_joined(id, data) # 玩家加入
NetworkManager.player_left(id)         # 玩家离开
```

## 操作说明

| 操作 | 按键 |
|------|------|
| 移动 | W/A/S/D |
| 瞄准 | 鼠标移动 |
| 射击 | 鼠标左键 |
| 交互 | E（待实现） |
| 背包 | Tab（待实现，M5阶段）|

## 开发阶段

| 阶段 | 内容 | 状态 |
|------|------|------|
| M0 | 项目初始化 | ✅ 完成 |
| M1 | 服务端骨架（Colyseus） | ✅ 完成 |
| **M2** | **客户端骨架（Godot）** | **✅ 当前** |
| M3 | 僵尸 AI 基础 | 🔜 待开发 |
| M4 | 波次系统 | 🔜 待开发 |
| M5 | 背包系统 | 🔜 待开发 |
| M6 | 完整地图（多楼层） | 🔜 待开发 |

## 导出

项目配置了两个导出预设（`export_presets.cfg`）：

1. **Windows Desktop** - x86_64 架构，64位
2. **Linux/X11** - x86_64 架构，64位

使用 Godot 4.2 编辑器的 "Project > Export" 功能导出。

## 许可证

MIT License - 详见项目根目录 LICENSE 文件
