extends CharacterBody2D

const SPEED := 80.0   # 像素/秒，RPG风格不要太快
const SEND_INTERVAL := 0.08

# 方向枚举
enum Dir { DOWN, LEFT, RIGHT, UP }

var health: int = 100
var hunger: int = 100
var is_local: bool = true
var _dir: int = Dir.DOWN
var _moving: bool = false
var _anim_timer: float = 0.0
var _anim_frame: int = 0  # 0=站立, 1=左脚, 2=右脚
const ANIM_SPEED := 0.2

var _send_timer: float = 0.0
var _last_pos: Vector2 = Vector2.ZERO

@onready var sprite: Sprite2D = $Sprite2D
@onready var name_label: Label = $NameLabel
@onready var shadow: Sprite2D = $Shadow

# 精灵表参数（24x32 × 3帧）
const SHEET_FRAME_W := 24
const SHEET_FRAME_H := 32

func _ready() -> void:
	name_label.text = NetworkManager.local_player_name if is_local else ""
	_update_sprite()

func _physics_process(delta: float) -> void:
	if not is_local:
		return

	var dir_vec: Vector2 = Vector2.ZERO
	if Input.is_action_pressed("move_up"):    dir_vec.y -= 1; _dir = Dir.UP
	if Input.is_action_pressed("move_down"):  dir_vec.y += 1; _dir = Dir.DOWN
	if Input.is_action_pressed("move_left"):  dir_vec.x -= 1; _dir = Dir.LEFT
	if Input.is_action_pressed("move_right"): dir_vec.x += 1; _dir = Dir.RIGHT

	dir_vec = dir_vec.normalized()
	_moving = dir_vec.length() > 0.01
	velocity = dir_vec * SPEED
	move_and_slide()

	# 帧动画
	if _moving:
		_anim_timer += delta
		if _anim_timer >= ANIM_SPEED:
			_anim_timer = 0.0
			_anim_frame = 1 if _anim_frame != 1 else 2
	else:
		_anim_frame = 0
	_update_sprite()

	# 发送位置（节流）
	_send_timer += delta
	if _send_timer >= SEND_INTERVAL:
		_send_timer = 0.0
		var dir_str: String = ["down","left","right","up"][_dir]
		NetworkManager.send_move(global_position.x, global_position.y, dir_str)

func _input(event: InputEvent) -> void:
	if not is_local: return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mp: Vector2 = get_global_mouse_position()
		NetworkManager.send_shoot(mp.x, mp.y)

func _update_sprite() -> void:
	if sprite == null: return
	# 行数 = 方向（Down=0, Left=1, Right=2, Up=3）（RPG Maker 标准顺序）
	var row: int = _dir  # Down=0, Left=1, Right=2, Up=3
	# 列 = 帧 (0=stand, 1=left, 2=right)
	var col: int = _anim_frame
	sprite.region_enabled = true
	sprite.region_rect = Rect2(col * SHEET_FRAME_W, row * SHEET_FRAME_H, SHEET_FRAME_W, SHEET_FRAME_H)

# 远端玩家调用
func set_remote_state(data: Dictionary) -> void:
	var tx: float = data.get("x", global_position.x)
	var ty: float = data.get("y", global_position.y)
	global_position = global_position.lerp(Vector2(tx, ty), 0.3)
	var d: String = data.get("dir", "down")
	_dir = {"down":0,"left":1,"right":2,"up":3}.get(d, 0)
	_moving = data.get("moving", false)
	_update_sprite()
	if not is_local:
		var pname: String = data.get("name", "")
		if name_label: name_label.text = pname

func set_health(v: int) -> void: health = v
func set_hunger(v: int) -> void: hunger = v
