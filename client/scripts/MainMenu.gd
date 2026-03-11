extends Control

# MainMenu.gd - Main menu logic for Mall Survival
# Handles player name input and joining the game server

var player_name: String = ""

@onready var player_name_input: LineEdit = $CenterContainer/PanelContainer/VBoxContainer/player_name_input
@onready var join_button: Button = $CenterContainer/PanelContainer/VBoxContainer/JoinButton
@onready var status_label: Label = $CenterContainer/PanelContainer/VBoxContainer/StatusLabel


func _ready() -> void:
	# Connect NetworkManager signals
	NetworkManager.connected.connect(_on_network_connected)
	NetworkManager.disconnected.connect(_on_network_disconnected)
	
	# Focus on name input
	player_name_input.grab_focus()
	player_name_input.text_submitted.connect(_on_name_submitted)
	
	# Show server address hint
	status_label.text = "服务器: ws://104.64.211.23:2567"


func _on_join_pressed() -> void:
	var name_text = player_name_input.text.strip_edges()
	if name_text.is_empty():
		_show_error("请输入玩家名！")
		return
	
	if name_text.length() < 2:
		_show_error("玩家名至少需要2个字符")
		return
	
	if name_text.length() > 16:
		_show_error("玩家名不能超过16个字符")
		return
	
	player_name = name_text
	_do_join()


func _on_name_submitted(text: String) -> void:
	_on_join_pressed()


func _do_join() -> void:
	join_button.disabled = true
	status_label.text = "正在连接服务器..."
	status_label.modulate = Color(0.5, 0.8, 1, 1)
	
	# Store player name globally
	NetworkManager.local_player_name = player_name
	
	# Connect to Colyseus server
	NetworkManager.connect_to_server(
		"ws://104.64.211.23:2567",
		"game",
		player_name
	)


func _on_network_connected() -> void:
	status_label.text = "连接成功！正在进入游戏..."
	status_label.modulate = Color(0.3, 1, 0.3, 1)
	
	# Small delay before scene transition for UX
	await get_tree().create_timer(0.5).timeout
	get_tree().change_scene_to_file("res://scenes/Game.tscn")


func _on_network_disconnected() -> void:
	join_button.disabled = false
	_show_error("连接失败，请重试")


func _show_error(msg: String) -> void:
	status_label.text = msg
	status_label.modulate = Color(1, 0.4, 0.4, 1)
