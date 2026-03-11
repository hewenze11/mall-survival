# 占位资源说明 / Placeholder Assets README

本目录用于存放游戏资源占位文件。

## 说明

在 M2 阶段，所有视觉元素均通过 Godot 内置的基础几何形状（Polygon2D、ColorRect 等）绘制，
无需外部资源文件。

## 预计在后续阶段添加的资源

| 资源类型 | 文件 | 说明 |
|---------|------|------|
| 玩家精灵图 | `player.png` | 玩家角色俯视图 |
| 僵尸精灵图 | `zombie.png` | 僵尸角色俯视图 |
| 地图瓦片集 | `tileset.png` | 商场地板、墙壁等 |
| 武器图标 | `weapons/*.png` | 各种武器的 HUD 图标 |
| UI 字体 | `fonts/main.ttf` | 游戏主字体 |
| 音效 | `sfx/*.ogg` | 射击、受伤、僵尸叫声等 |
| 背景音乐 | `music/bgm.ogg` | 游戏背景音乐 |

## 图标

Godot 4 需要一个 `icon.svg` 文件作为项目图标，使用默认的 Godot 图标即可。
