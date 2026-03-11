extends CanvasLayer

# Inventory.gd - 背包UI控制器
# Tab 键开关，显示玩家背包内容，支持使用物品

# 物品图标贴图（像素风格）
const ITEM_ICON_PATHS: Dictionary = {
	"food":             "res://assets/icons/food_can.png",
	"food_can":         "res://assets/icons/food_can.png",
	"food_biscuit":     "res://assets/icons/food_biscuit.png",
	"medicine":         "res://assets/icons/medicine_kit.png",
	"medicine_kit":     "res://assets/icons/medicine_kit.png",
	"medicine_bandage": "res://assets/icons/medicine_bandage.png",
	"weapon":           "res://assets/icons/weapon_pistol.png",
	"pistol":           "res://assets/icons/weapon_pistol.png",
	"shotgun":          "res://assets/icons/weapon_shotgun.png",
	"weapon_pistol":    "res://assets/icons/weapon_pistol.png",
	"weapon_shotgun":   "res://assets/icons/weapon_shotgun.png",
	"ammo":             "res://assets/icons/ammo_pistol.png",
	"ammo_pistol":      "res://assets/icons/ammo_pistol.png",
	"ammo_shotgun":     "res://assets/icons/ammo_shotgun.png",
}

var _visible_panel: bool = false
var _item_buttons: Array = []
var _icon_cache: Dictionary = {}

@onready var inventory_panel: PanelContainer = $inventory_panel
@onready var item_grid: GridContainer = $inventory_panel/VBoxContainer/ScrollContainer/item_grid
@onready var weapon_label: Label = $inventory_panel/VBoxContainer/weapon_label
@onready var ammo_label: Label = $inventory_panel/VBoxContainer/ammo_label
@onready var title_label: Label = $inventory_panel/VBoxContainer/title_label
@onready var close_button: Button = $inventory_panel/VBoxContainer/close_button


func _ready() -> void:
	inventory_panel.visible = false
	_visible_panel = false

	if close_button:
		close_button.pressed.connect(hide_inventory)

	NetworkManager.state_updated.connect(_on_state_updated)
	print("[Inventory] Inventory UI ready")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			toggle_visibility()
			get_viewport().set_input_as_handled()


func toggle_visibility() -> void:
	_visible_panel = !_visible_panel
	inventory_panel.visible = _visible_panel
	if _visible_panel:
		_refresh_inventory()


func hide_inventory() -> void:
	_visible_panel = false
	inventory_panel.visible = false


func _on_state_updated(_state: Dictionary) -> void:
	if _visible_panel:
		_refresh_inventory()


func _get_icon_texture(item_type: String, item_name: String) -> Texture2D:
	# Try exact item_name first, then item_type
	for key in [item_name, item_type]:
		if ITEM_ICON_PATHS.has(key):
			var path = ITEM_ICON_PATHS[key]
			if not _icon_cache.has(path):
				_icon_cache[path] = load(path)
			return _icon_cache[path]
	return null


func _refresh_inventory() -> void:
	for btn in _item_buttons:
		if is_instance_valid(btn):
			btn.queue_free()
	_item_buttons.clear()

	var my_id = NetworkManager.local_player_id
	var state = NetworkManager.game_state

	if not state.has("players"):
		return

	var players = state["players"]
	if not players.has(my_id):
		return

	var player_data = players[my_id]

	# Update weapon/ammo labels
	var weapon = player_data.get("equippedWeapon", "none")
	var player_ammo = player_data.get("ammo", 0)

	if weapon_label:
		var wtext = "none"
		if weapon == "pistol":
			wtext = "手枪"
		elif weapon == "shotgun":
			wtext = "霰弹枪"
		weapon_label.text = "装备: %s" % wtext

	if ammo_label:
		ammo_label.text = "弹药: %d" % player_ammo

	var inventory = player_data.get("inventory", {})
	var inv_count = player_data.get("inventoryCount", 0)

	if title_label:
		title_label.text = "🎒 背包 [%d/20]" % inv_count

	if typeof(inventory) != TYPE_DICTIONARY:
		return

	for item_key in inventory:
		var item_data = inventory[item_key]
		if typeof(item_data) != TYPE_DICTIONARY:
			continue

		var item_name = item_data.get("itemName", item_key)
		var item_type = item_data.get("itemType", "")
		var quantity  = item_data.get("quantity", 1)
		var value     = item_data.get("value", 0)

		# Build a VBoxContainer card: icon + label
		var card = PanelContainer.new()
		card.custom_minimum_size = Vector2(80, 90)
		card.tooltip_text = _get_item_tooltip(item_type, item_name, value)

		var vbox = VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		card.add_child(vbox)

		# Icon
		var tex = _get_icon_texture(item_type, item_name)
		if tex:
			var icon = TextureRect.new()
			icon.texture = tex
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(32, 32)
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			vbox.add_child(icon)
		else:
			var fallback = Label.new()
			fallback.text = _get_fallback_emoji(item_type)
			fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			fallback.theme_override_font_sizes/font_size = 20
			vbox.add_child(fallback)

		# Name + quantity label
		var lbl = Label.new()
		lbl.text = "%s\n×%d" % [item_name, quantity]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.theme_override_font_sizes/font_size = 10
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		lbl.add_theme_color_override("font_color", _get_item_color(item_type))
		vbox.add_child(lbl)

		# Click handler
		var key_capture = item_key
		card.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_on_item_clicked(key_capture)
		)

		item_grid.add_child(card)
		_item_buttons.append(card)


func _get_fallback_emoji(item_type: String) -> String:
	match item_type:
		"food":     return "🍞"
		"medicine": return "💊"
		"weapon":   return "🔫"
		"ammo":     return "🔴"
	return "📦"


func _get_item_tooltip(item_type: String, item_name: String, value: int) -> String:
	match item_type:
		"food":     return "%s\n恢复饥饿 +%d" % [item_name, value]
		"medicine": return "%s\n恢复血量 +%d" % [item_name, value]
		"weapon":   return "%s\n伤害 %d\n点击装备" % [item_name, value]
		"ammo":     return "%s\n+%d发\n点击装填" % [item_name, value]
	return item_name


func _get_item_color(item_type: String) -> Color:
	match item_type:
		"food":     return Color(0.9, 0.7, 0.2)
		"medicine": return Color(0.3, 1.0, 0.5)
		"weapon":   return Color(1.0, 0.5, 0.2)
		"ammo":     return Color(0.8, 0.8, 1.0)
	return Color(1, 1, 1)


func _on_item_clicked(item_key: String) -> void:
	print("[Inventory] Using item: %s" % item_key)
	NetworkManager.send_use_item(item_key)
	await get_tree().create_timer(0.15).timeout
	_refresh_inventory()
