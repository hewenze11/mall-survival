extends CanvasLayer

# Inventory.gd - 背包UI控制器
# Tab 键开关，显示玩家背包内容，支持使用物品

var _visible_panel: bool = false
var _item_buttons: Array = []

@onready var inventory_panel: PanelContainer = $inventory_panel
@onready var item_grid: GridContainer = $inventory_panel/VBoxContainer/ScrollContainer/item_grid
@onready var weapon_label: Label = $inventory_panel/VBoxContainer/weapon_label
@onready var ammo_label: Label = $inventory_panel/VBoxContainer/ammo_label
@onready var title_label: Label = $inventory_panel/VBoxContainer/title_label
@onready var close_button: Button = $inventory_panel/VBoxContainer/close_button


func _ready() -> void:
	# 初始隐藏
	inventory_panel.visible = false
	_visible_panel = false
	
	# 关闭按钮
	if close_button:
		close_button.pressed.connect(hide_inventory)
	
	# 连接状态更新信号
	NetworkManager.state_updated.connect(_on_state_updated)
	
	print("[Inventory] Inventory UI ready")


func _input(event: InputEvent) -> void:
	# Tab 键切换背包显示
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


func _on_state_updated(state: Dictionary) -> void:
	# 如果背包开着，实时刷新
	if _visible_panel:
		_refresh_inventory()


func _refresh_inventory() -> void:
	# 清空现有物品按钮
	for btn in _item_buttons:
		if is_instance_valid(btn):
			btn.queue_free()
	_item_buttons.clear()
	
	# 从服务端状态获取本地玩家数据
	var my_id = NetworkManager.local_player_id
	var state = NetworkManager.game_state
	
	if not state.has("players"):
		return
	
	var players = state["players"]
	if not players.has(my_id):
		return
	
	var player_data = players[my_id]
	
	# 更新武器和弹药信息
	var weapon = player_data.get("equippedWeapon", "none")
	var player_ammo = player_data.get("ammo", 0)
	
	if weapon_label:
		var weapon_text = "none"
		if weapon == "pistol":
			weapon_text = "🔫 手枪"
		elif weapon == "shotgun":
			weapon_text = "💥 霰弹枪"
		weapon_label.text = "装备: %s" % weapon_text
	
	if ammo_label:
		ammo_label.text = "弹药: %d" % player_ammo
	
	# 显示背包物品
	var inventory = player_data.get("inventory", {})
	var inv_count = player_data.get("inventoryCount", 0)
	
	# 更新标题显示容量
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
		var quantity = item_data.get("quantity", 1)
		var value = item_data.get("value", 0)
		
		# 创建物品按钮
		var btn = Button.new()
		btn.text = _format_item_text(item_type, item_name, quantity, value)
		btn.custom_minimum_size = Vector2(130, 60)
		btn.tooltip_text = _get_item_tooltip(item_type, item_name, value)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD
		
		# 按物品类型设置颜色
		var color = _get_item_color(item_type)
		btn.add_theme_color_override("font_color", color)
		
		# 绑定点击事件
		var key_capture = item_key
		btn.pressed.connect(func(): _on_item_clicked(key_capture))
		
		item_grid.add_child(btn)
		_item_buttons.append(btn)


func _format_item_text(item_type: String, item_name: String, quantity: int, _value: int) -> String:
	var icon = ""
	match item_type:
		"food":     icon = "🍞"
		"medicine": icon = "💊"
		"weapon":
			if item_name == "pistol":
				icon = "🔫"
			else:
				icon = "💥"
		"ammo":     icon = "🔴"
		_:          icon = "📦"
	return "%s %s\n×%d" % [icon, item_name, quantity]


func _get_item_tooltip(item_type: String, item_name: String, value: int) -> String:
	match item_type:
		"food":
			return "%s\n恢复饥饿 +%d" % [item_name, value]
		"medicine":
			return "%s\n恢复血量 +%d" % [item_name, value]
		"weapon":
			if item_name == "pistol":
				return "手枪\n伤害 %d\n点击装备" % value
			elif item_name == "shotgun":
				return "霰弹枪\n伤害 %d\n点击装备" % value
			return "%s\n点击装备" % item_name
		"ammo":
			return "%s\n+%d发\n点击装填" % [item_name, value]
	return item_name


func _get_item_color(item_type: String) -> Color:
	match item_type:
		"food":     return Color(0.9, 0.7, 0.2)   # 金黄
		"medicine": return Color(0.3, 1.0, 0.5)   # 绿色
		"weapon":   return Color(1.0, 0.5, 0.2)   # 橙色
		"ammo":     return Color(0.8, 0.8, 1.0)   # 淡蓝
	return Color(1, 1, 1)


func _on_item_clicked(item_key: String) -> void:
	print("[Inventory] Using item: %s" % item_key)
	NetworkManager.send_use_item(item_key)
	# 短暂延迟后刷新UI（等待服务端响应）
	await get_tree().create_timer(0.15).timeout
	_refresh_inventory()
