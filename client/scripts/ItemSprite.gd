extends Node2D

# ItemSprite.gd - 地图上物资的可视化节点
# 玩家靠近时显示交互提示，按 E 键拾取

const PICKUP_DISTANCE: float = 100.0

# 物品图标贴图映射（像素风格 PNG）
const ICON_TEXTURES: Dictionary = {
	"food_can":         "res://assets/icons/food_can.png",
	"food_biscuit":     "res://assets/icons/food_biscuit.png",
	"food":             "res://assets/icons/food_can.png",
	"medicine_kit":     "res://assets/icons/medicine_kit.png",
	"medicine_bandage": "res://assets/icons/medicine_bandage.png",
	"medicine":         "res://assets/icons/medicine_kit.png",
	"weapon_pistol":    "res://assets/icons/weapon_pistol.png",
	"weapon_shotgun":   "res://assets/icons/weapon_shotgun.png",
	"weapon":           "res://assets/icons/weapon_pistol.png",
	"ammo_pistol":      "res://assets/icons/ammo_pistol.png",
	"ammo_shotgun":     "res://assets/icons/ammo_shotgun.png",
	"ammo":             "res://assets/icons/ammo_pistol.png",
}

var item_id: String = ""
var item_type: String = ""
var item_name: String = ""
var item_floor: int = 1

var _prompt_visible: bool = false

@onready var name_label: Label = $name_label
@onready var prompt_label: Label = $prompt_label
@onready var icon_sprite: Sprite2D = $icon_sprite


func _ready() -> void:
	if prompt_label:
		prompt_label.visible = false


func initialize(id: String, type: String, name: String, x: float, y: float, floor: int) -> void:
	item_id = id
	item_type = type
	item_name = name
	item_floor = floor
	global_position = Vector2(x, y)
	
	if name_label:
		name_label.text = name
	
	# 加载对应的像素图标
	if icon_sprite:
		var tex_path = ICON_TEXTURES.get(type, "")
		if tex_path == "":
			# 尝试前缀匹配（如 "food_xxx" → "food"）
			for key in ICON_TEXTURES:
				if type.begins_with(key):
					tex_path = ICON_TEXTURES[key]
					break
		if tex_path != "":
			icon_sprite.texture = load(tex_path)
			icon_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(_delta: float) -> void:
	# 检测本地玩家距离，显示交互提示
	var game = get_tree().get_first_node_in_group("game")
	if not game:
		return
	
	var local_player = game.get("local_player")
	if not local_player or not is_instance_valid(local_player):
		return
	
	var dist = global_position.distance_to(local_player.global_position)
	var in_range = dist <= PICKUP_DISTANCE
	
	if in_range != _prompt_visible:
		_prompt_visible = in_range
		if prompt_label:
			prompt_label.visible = in_range
	
	# E 键拾取
	if in_range and Input.is_action_just_pressed("interact"):
		NetworkManager.send_pickup(item_id)
