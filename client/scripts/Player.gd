extends CharacterBody2D

const SPEED: float = 200.0
const MOVE_SEND_INTERVAL: float = 0.05

const TEX_DOWN  = preload("res://assets/characters/player_down.png")
const TEX_UP    = preload("res://assets/characters/player_up.png")
const TEX_LEFT  = preload("res://assets/characters/player_left.png")
const TEX_RIGHT = preload("res://assets/characters/player_right.png")

var health: int = 100
var hunger: int = 100
var equipped_weapon: String = "none"
var ammo: int = 0
var _move_timer: float = 0.0
var _last_sent_pos: Vector2 = Vector2.ZERO

@onready var name_label: Label = $NameLabel
@onready var direction_indicator: Line2D = $DirectionIndicator
@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	name_label.text = NetworkManager.local_player_name
	if sprite:
		sprite.texture = TEX_DOWN
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	NetworkManager.damage_received.connect(_on_damage_received)

func _physics_process(delta: float) -> void:
	_move_timer += delta

	# 用全局方向移动，不受节点 rotation 影响
	var dir = Vector2.ZERO
	if Input.is_action_pressed("move_up"):    dir.y -= 1
	if Input.is_action_pressed("move_down"):  dir.y += 1
	if Input.is_action_pressed("move_left"):  dir.x -= 1
	if Input.is_action_pressed("move_right"): dir.x += 1
	dir = dir.normalized()
	velocity = dir * SPEED

	# 更新朝向贴图（不旋转节点，只换贴图）
	if dir.length() > 0.01 and sprite:
		if abs(dir.x) >= abs(dir.y):
			sprite.texture = TEX_RIGHT if dir.x > 0 else TEX_LEFT
		else:
			sprite.texture = TEX_DOWN if dir.y > 0 else TEX_UP

	# 朝向指示器朝向鼠标（仅 Line2D，不旋转整个节点）
	if direction_indicator:
		var mouse_local = to_local(get_global_mouse_position())
		var mouse_dir = mouse_local.normalized() * 20.0
		direction_indicator.clear_points()
		direction_indicator.add_point(Vector2.ZERO)
		direction_indicator.add_point(mouse_dir)

	move_and_slide()

	# 发送位置给服务端（节流）
	if _move_timer >= MOVE_SEND_INTERVAL:
		_move_timer = 0.0
		if global_position.distance_to(_last_sent_pos) > 0.5 or not velocity.is_zero_approx():
			_last_sent_pos = global_position
			var angle = global_position.angle_to_point(get_global_mouse_position())
			NetworkManager.send_move(global_position.x, global_position.y, angle)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_world = get_global_mouse_position()
		NetworkManager.send_shoot(mouse_world.x, mouse_world.y)
		if direction_indicator:
			direction_indicator.default_color = Color(1, 0.8, 0, 1)
			await get_tree().create_timer(0.08).timeout
			if is_instance_valid(direction_indicator):
				direction_indicator.default_color = Color(1, 1, 0, 0.7)

func _on_damage_received(amount: int) -> void:
	health = max(0, health - amount)
	modulate = Color(1, 0.2, 0.2, 1)
	await get_tree().create_timer(0.15).timeout
	if is_instance_valid(self): modulate = Color(1, 1, 1, 1)
	var hud = get_tree().get_first_node_in_group("hud")
	if hud: hud.update_health(health)

func set_health(v: int) -> void: health = v
func set_hunger(v: int) -> void: hunger = v
func set_weapon(w: String, a: int) -> void: equipped_weapon = w; ammo = a
