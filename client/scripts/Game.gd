extends Node2D

const PLAYER_SCENE = preload("res://scenes/Player.tscn")
const TILE_SIZE := 16
const MAP_W := 40  # tiles
const MAP_H := 30  # tiles

var local_player: CharacterBody2D = null
var remote_players: Dictionary = {}  # id -> Node
var _countdown := 300.0
var _phase := "WAITING"
var _wave := 1

@onready var tile_layer: Node2D = $TileLayer
@onready var entities_layer: Node2D = $EntitiesLayer
@onready var camera: Camera2D = $Camera2D
@onready var hud = $HUD

func _ready() -> void:
	_build_tilemap()
	_spawn_local_player()

	NetworkManager.state_updated.connect(_on_state)
	NetworkManager.player_joined.connect(_on_player_joined)
	NetworkManager.player_left.connect(_on_player_left)
	NetworkManager.phase_changed.connect(_on_phase_changed)
	NetworkManager.disconnected.connect(_on_disconnected)

	if hud:
		hud.update_health(100)
		hud.update_hunger(100)
		hud.update_wave(1)
		hud.update_phase("PREP", 300.0)

func _process(delta: float) -> void:
	if _phase == "PREP" and _countdown > 0:
		_countdown -= delta
		if hud: hud.update_phase(_phase, _countdown)
	# Camera follows local player
	if local_player and is_instance_valid(local_player):
		camera.global_position = local_player.global_position

# ─── 地图构建（简单平铺地板 + 边墙）───────────────────────────
func _build_tilemap() -> void:
	var floor_tex = load("res://assets/tileset/floor.png")
	var wall_tex  = load("res://assets/tileset/wall.png")

	for ty in range(MAP_H):
		for tx in range(MAP_W):
			var s := Sprite2D.new()
			s.position = Vector2(tx * TILE_SIZE + TILE_SIZE/2.0, ty * TILE_SIZE + TILE_SIZE/2.0)
			s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			var is_wall = (tx == 0 or ty == 0 or tx == MAP_W-1 or ty == MAP_H-1)
			s.texture = wall_tex if is_wall else floor_tex
			tile_layer.add_child(s)

func _spawn_local_player() -> void:
	local_player = PLAYER_SCENE.instantiate()
	local_player.is_local = true
	entities_layer.add_child(local_player)
	local_player.global_position = Vector2(MAP_W * TILE_SIZE / 2.0, MAP_H * TILE_SIZE / 2.0)
	camera.reparent(local_player)
	camera.position = Vector2.ZERO

func _spawn_remote_player(pid: String, data: Dictionary) -> void:
	if pid == NetworkManager.local_player_id: return
	if remote_players.has(pid): return
	var p = PLAYER_SCENE.instantiate()
	p.is_local = false
	entities_layer.add_child(p)
	p.global_position = Vector2(data.get("x", 320.0), data.get("y", 240.0))
	remote_players[pid] = p

func _on_state(state: Dictionary) -> void:
	if state.has("wave"): _wave = state["wave"]
	if state.has("phase"): _phase = state["phase"]
	if state.has("countdown"): _countdown = state["countdown"]

	if state.has("players"):
		var players = state["players"]
		for pid in players:
			var pdata = players[pid]
			if pid == NetworkManager.local_player_id:
				if local_player:
					if pdata.has("health"): local_player.set_health(pdata["health"])
					if pdata.has("hunger"): local_player.set_hunger(pdata["hunger"])
					if hud:
						hud.update_health(pdata.get("health", 100))
						hud.update_hunger(pdata.get("hunger", 100))
						hud.update_wave(state.get("wave", _wave))
						hud.update_weapon(pdata.get("equippedWeapon","none"), pdata.get("ammo",0))
			else:
				if remote_players.has(pid):
					remote_players[pid].set_remote_state(pdata)
				else:
					_spawn_remote_player(pid, pdata)

func _on_player_joined(pid: String, data: Dictionary) -> void:
	_spawn_remote_player(pid, data)

func _on_player_left(pid: String) -> void:
	if remote_players.has(pid):
		remote_players[pid].queue_free()
		remote_players.erase(pid)

func _on_phase_changed(phase: String, t: float) -> void:
	_phase = phase; _countdown = t
	if hud: hud.update_phase(phase, t)

func _on_disconnected() -> void:
	await get_tree().create_timer(1.0).timeout
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
