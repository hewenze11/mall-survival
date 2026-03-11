extends Node

# NetworkManager.gd - Colyseus WebSocket Network Manager (Autoload Singleton)
# Handles all network communication with the Colyseus game server
# Protocol: JSON over WebSocket (simplified Colyseus-compatible)

# Signals
signal connected
signal disconnected
signal state_updated(state: Dictionary)
signal player_joined(player_id: String, player_data: Dictionary)
signal player_left(player_id: String)
signal game_phase_updated(phase: String, countdown: float)
signal damage_received(amount: int)
signal room_error(code: int, message: String)

# Colyseus message protocol opcodes
const PROTOCOL_JOIN = 10
const PROTOCOL_JOIN_ERROR = 11
const PROTOCOL_LEAVE = 12
const PROTOCOL_ROOM_DATA = 13
const PROTOCOL_ROOM_STATE = 14
const PROTOCOL_ROOM_STATE_PATCH = 15
const PROTOCOL_BATCH = 16
const PROTOCOL_ERROR = 17

# Connection state
enum ConnectionState { DISCONNECTED, CONNECTING, CONNECTED, IN_ROOM }

var _ws: WebSocketPeer = null
var _state: ConnectionState = ConnectionState.DISCONNECTED
var _room_id: String = ""
var _session_id: String = ""
var _reconnect_timer: float = 0.0
var _reconnect_delay: float = 3.0
var _move_throttle_timer: float = 0.0
var _move_throttle_interval: float = 0.05  # 50ms throttle

# Public data
var local_player_name: String = ""
var local_player_id: String = ""
var game_state: Dictionary = {}

# Connection parameters (stored for reconnect)
var _server_url: String = ""
var _room_name: String = ""


func _ready() -> void:
	set_process(true)
	print("[NetworkManager] Initialized")


func _process(delta: float) -> void:
	if _ws == null:
		return
	
	_ws.poll()
	
	var ws_state = _ws.get_ready_state()
	
	match ws_state:
		WebSocketPeer.STATE_OPEN:
			if _state == ConnectionState.CONNECTING:
				_on_ws_open()
			_receive_messages()
		
		WebSocketPeer.STATE_CLOSED:
			if _state != ConnectionState.DISCONNECTED:
				var code = _ws.get_close_code()
				var reason = _ws.get_close_reason()
				print("[NetworkManager] WebSocket closed: %d - %s" % [code, reason])
				_state = ConnectionState.DISCONNECTED
				disconnected.emit()
	
	# Move throttle timer
	if _move_throttle_timer > 0:
		_move_throttle_timer -= delta


# ============================================================
# Public API
# ============================================================

func connect_to_server(server_url: String, room_name: String, player_name: String) -> void:
	print("[NetworkManager] Connecting to %s/%s as '%s'" % [server_url, room_name, player_name])
	
	_server_url = server_url
	_room_name = room_name
	local_player_name = player_name
	
	# Build Colyseus room join URL
	# Colyseus WebSocket endpoint: ws://<host>/<room>?playerName=<name>
	var room_url = "%s/%s?playerName=%s" % [
		server_url,
		room_name,
		player_name.uri_encode()
	]
	
	_ws = WebSocketPeer.new()
	_ws.supported_protocols = PackedStringArray(["binary"])
	
	var err = _ws.connect_to_url(room_url)
	if err != OK:
		push_error("[NetworkManager] Failed to connect: %d" % err)
		disconnected.emit()
		return
	
	_state = ConnectionState.CONNECTING
	print("[NetworkManager] WebSocket connecting to: %s" % room_url)


func disconnect_from_server() -> void:
	if _ws != null and _state != ConnectionState.DISCONNECTED:
		_ws.close(1000, "Client disconnecting")
		_state = ConnectionState.DISCONNECTED


func send_move(x: float, y: float, direction: float) -> void:
	if _state != ConnectionState.IN_ROOM:
		return
	if _move_throttle_timer > 0:
		return
	
	_move_throttle_timer = _move_throttle_interval
	_send_room_message({
		"type": "move",
		"x": snappedf(x, 0.1),
		"y": snappedf(y, 0.1),
		"direction": snappedf(direction, 0.01)
	})


func send_shoot(target_x: float, target_y: float) -> void:
	if _state != ConnectionState.IN_ROOM:
		return
	_send_room_message({
		"type": "shoot",
		"targetX": target_x,
		"targetY": target_y
	})


func send_interact() -> void:
	if _state != ConnectionState.IN_ROOM:
		return
	_send_room_message({"type": "interact"})


func is_connected_to_room() -> bool:
	return _state == ConnectionState.IN_ROOM


# ============================================================
# Internal WebSocket handling
# ============================================================

func _on_ws_open() -> void:
	print("[NetworkManager] WebSocket opened, performing Colyseus join handshake")
	_state = ConnectionState.CONNECTED
	
	# Send Colyseus join request as JSON
	# The server expects a join message with player info
	var join_msg = {
		"protocol": PROTOCOL_JOIN,
		"playerName": local_player_name,
		"version": "1.0"
	}
	_send_json(join_msg)


func _receive_messages() -> void:
	while _ws.get_available_packet_count() > 0:
		var packet = _ws.get_packet()
		_handle_packet(packet)


func _handle_packet(data: PackedByteArray) -> void:
	# Try to parse as JSON text
	var text = data.get_string_from_utf8()
	if text.is_empty():
		return
	
	var json = JSON.new()
	var err = json.parse(text)
	if err != OK:
		print("[NetworkManager] JSON parse error: %s in '%s'" % [json.get_error_message(), text])
		return
	
	var msg = json.get_data()
	if typeof(msg) != TYPE_DICTIONARY:
		return
	
	_dispatch_message(msg)


func _dispatch_message(msg: Dictionary) -> void:
	var protocol = msg.get("protocol", -1)
	var msg_type = msg.get("type", "")
	
	# Handle by protocol code first
	match protocol:
		PROTOCOL_JOIN:
			_handle_join_success(msg)
			return
		PROTOCOL_JOIN_ERROR:
			_handle_join_error(msg)
			return
		PROTOCOL_ROOM_STATE:
			_handle_state_full(msg)
			return
		PROTOCOL_ROOM_STATE_PATCH:
			_handle_state_patch(msg)
			return
		PROTOCOL_ROOM_DATA:
			_handle_room_data(msg)
			return
		PROTOCOL_LEAVE:
			print("[NetworkManager] Server requested leave")
			disconnect_from_server()
			return
	
	# Fallback: handle by type string (for our simplified JSON protocol)
	match msg_type:
		"joined":
			_handle_join_success(msg)
		"error":
			print("[NetworkManager] Server error: %s" % msg.get("message", "unknown"))
			room_error.emit(msg.get("code", -1), msg.get("message", ""))
		"state":
			_handle_state_full(msg)
		"patch":
			_handle_state_patch(msg)
		"playerJoined":
			var pid = msg.get("id", "")
			var pdata = msg.get("player", {})
			if not pid.is_empty():
				player_joined.emit(pid, pdata)
		"playerLeft":
			var pid = msg.get("id", "")
			if not pid.is_empty():
				player_left.emit(pid)
		"phase":
			var phase = msg.get("phase", "PREP")
			var countdown = msg.get("countdown", 0.0)
			game_phase_updated.emit(phase, countdown)
		"damage":
			var amount = msg.get("amount", 0)
			damage_received.emit(amount)
		_:
			if msg_type != "":
				print("[NetworkManager] Unknown message type: %s" % msg_type)


func _handle_join_success(msg: Dictionary) -> void:
	_session_id = msg.get("sessionId", msg.get("id", ""))
	local_player_id = _session_id
	_state = ConnectionState.IN_ROOM
	print("[NetworkManager] Joined room! Session ID: %s" % _session_id)
	connected.emit()
	
	# If initial state is included
	if msg.has("state"):
		_process_state(msg["state"])


func _handle_join_error(msg: Dictionary) -> void:
	print("[NetworkManager] Join error: %s" % msg.get("message", "Unknown error"))
	room_error.emit(msg.get("code", -1), msg.get("message", ""))
	disconnect_from_server()
	disconnected.emit()


func _handle_state_full(msg: Dictionary) -> void:
	var new_state = msg.get("state", msg)
	_process_state(new_state)


func _handle_state_patch(msg: Dictionary) -> void:
	# Apply patch to current state
	var patch = msg.get("patch", msg)
	if typeof(patch) == TYPE_DICTIONARY:
		for key in patch:
			game_state[key] = patch[key]
		state_updated.emit(game_state)


func _handle_room_data(msg: Dictionary) -> void:
	# Handle room data messages (routed to room data handler)
	var data = msg.get("data", msg)
	_dispatch_message(data)


func _process_state(new_state: Dictionary) -> void:
	game_state = new_state
	state_updated.emit(game_state)
	
	# Emit player events for any players in the state
	if new_state.has("players"):
		var players = new_state["players"]
		if typeof(players) == TYPE_DICTIONARY:
			for pid in players:
				player_joined.emit(pid, players[pid])


# ============================================================
# Low-level send helpers
# ============================================================

func _send_room_message(data: Dictionary) -> void:
	# Wrap in Colyseus room data protocol
	var envelope = {
		"protocol": PROTOCOL_ROOM_DATA,
		"data": data
	}
	_send_json(envelope)


func _send_json(data: Dictionary) -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var text = JSON.stringify(data)
	var packet = text.to_utf8_buffer()
	var err = _ws.send(packet, WebSocketPeer.WRITE_MODE_TEXT)
	if err != OK:
		push_error("[NetworkManager] Send error: %d" % err)
