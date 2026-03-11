extends Node

# NetworkManager.gd - Colyseus Matchmaker-based Network Manager (Autoload Singleton)
# Correct Colyseus connection flow:
#   1. HTTP POST /matchmake/joinOrCreate/<room> → get sessionId + roomId
#   2. WebSocket ws://<host>/<roomId>?sessionId=<sessionId>

# Signals
signal connected
signal disconnected
signal state_updated(state: Dictionary)
signal player_joined(player_id: String, player_data: Dictionary)
signal player_left(player_id: String)
signal game_phase_updated(phase: String, countdown: float)
signal damage_received(amount: int)
signal room_error(code: int, message: String)
signal pickup_result(success: bool, item_id: String)
signal use_item_result(success: bool, item_key: String)
signal items_updated(items: Dictionary)

# M6: 战斗系统信号
signal shoot_fx_received(data: Dictionary)
signal player_hit_received(data: Dictionary)
signal zombie_hit_received(data: Dictionary)
signal zombie_dead_received(zombie_id: String)
signal player_dead_received(player_id: String)
signal no_ammo_received()

# Colyseus protocol opcodes
const PROTOCOL_JOIN = 10
const PROTOCOL_JOIN_ERROR = 11
const PROTOCOL_LEAVE = 12
const PROTOCOL_ROOM_DATA = 13
const PROTOCOL_ROOM_STATE = 14
const PROTOCOL_ROOM_STATE_PATCH = 15
const PROTOCOL_BATCH = 16
const PROTOCOL_ERROR = 17

enum ConnectionState { DISCONNECTED, CONNECTING, CONNECTED, IN_ROOM }

var _ws: WebSocketPeer = null
var _state: ConnectionState = ConnectionState.DISCONNECTED
var _session_id: String = ""
var _move_throttle_timer: float = 0.0
var _move_throttle_interval: float = 0.05  # 50ms throttle

# Public data
var local_player_name: String = ""
var local_player_id: String = ""
var my_session_id: String = ""
var game_state: Dictionary = {}

# Connection parameters
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
	_state = ConnectionState.CONNECTING
	# Phase 1: HTTP matchmake
	_http_matchmake(server_url, room_name, player_name)


func _http_matchmake(server_url: String, room_name: String, player_name: String) -> void:
	# Convert ws:// → http:// for the matchmaker endpoint
	var http_url = server_url.replace("ws://", "http://").replace("wss://", "https://")
	var matchmake_url = "%s/matchmake/joinOrCreate/%s" % [http_url, room_name]
	print("[NetworkManager] Matchmaking at: %s" % matchmake_url)

	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result, response_code, headers, body):
		_on_matchmake_response(result, response_code, body, http)
	)

	var headers = ["Content-Type: application/json"]
	var body = JSON.stringify({"playerName": player_name})
	var err = http.request(matchmake_url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		push_error("[NetworkManager] HTTP matchmake request failed: %d" % err)
		_state = ConnectionState.DISCONNECTED
		disconnected.emit()


func _on_matchmake_response(result: int, response_code: int, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_error("[NetworkManager] Matchmake failed: result=%d code=%d body=%s" % [
			result, response_code, body.get_string_from_utf8()
		])
		_state = ConnectionState.DISCONNECTED
		disconnected.emit()
		return

	var text = body.get_string_from_utf8()
	var json = JSON.new()
	if json.parse(text) != OK:
		push_error("[NetworkManager] Matchmake JSON parse error in: %s" % text)
		_state = ConnectionState.DISCONNECTED
		disconnected.emit()
		return

	var data = json.get_data()
	print("[NetworkManager] Matchmake OK: %s" % text.left(300))

	# Colyseus response: {"sessionId":"xxx","room":{"roomId":"xxx","processId":"xxx"},"devMode":false}
	var session_id = data.get("sessionId", "")
	var room_data = data.get("room", {})
	var room_id = room_data.get("roomId", "")

	if session_id.is_empty() or room_id.is_empty():
		push_error("[NetworkManager] Missing sessionId or roomId in matchmake response")
		_state = ConnectionState.DISCONNECTED
		disconnected.emit()
		return

	_session_id = session_id
	local_player_id = session_id
	my_session_id = session_id

	# Phase 2: Connect WebSocket with roomId + sessionId
	var ws_url = "%s/%s?sessionId=%s" % [_server_url, room_id, session_id]
	print("[NetworkManager] WS connecting: %s" % ws_url)
	_connect_websocket(ws_url)


func _connect_websocket(ws_url: String) -> void:
	_ws = WebSocketPeer.new()
	_ws.supported_protocols = PackedStringArray(["binary"])
	var err = _ws.connect_to_url(ws_url)
	if err != OK:
		push_error("[NetworkManager] WebSocket connect failed: %d" % err)
		_state = ConnectionState.DISCONNECTED
		disconnected.emit()


func disconnect_from_server() -> void:
	if _ws != null and _state != ConnectionState.DISCONNECTED:
		_ws.close(1000, "Client disconnecting")
		_state = ConnectionState.DISCONNECTED


func send_move(x: float, y: float, direction: float) -> void:
	if _state != ConnectionState.IN_ROOM or _move_throttle_timer > 0:
		return
	_move_throttle_timer = _move_throttle_interval
	_send_msg({
		"type": "move",
		"x": snappedf(x, 0.1),
		"y": snappedf(y, 0.1),
		"direction": snappedf(direction, 0.01)
	})


func send_shoot(target_x: float, target_y: float) -> void:
	if _state != ConnectionState.IN_ROOM:
		return
	_send_msg({"type": "shoot", "targetX": target_x, "targetY": target_y})


func send_pickup(item_id: String) -> void:
	if _state != ConnectionState.IN_ROOM:
		return
	_send_msg({"type": "pickup", "itemId": item_id})


func send_use_item(item_key: String) -> void:
	if _state != ConnectionState.IN_ROOM:
		return
	_send_msg({"type": "use_item", "itemKey": item_key})


func send_interact() -> void:
	if _state != ConnectionState.IN_ROOM:
		return
	_send_msg({"type": "interact"})


func is_connected_to_room() -> bool:
	return _state == ConnectionState.IN_ROOM


# ============================================================
# Internal WebSocket handling
# ============================================================

func _on_ws_open() -> void:
	# Matchmaker already handled authentication — WebSocket open means we're in the room
	print("[NetworkManager] WebSocket connected to room!")
	_state = ConnectionState.IN_ROOM
	connected.emit()


func _receive_messages() -> void:
	while _ws.get_available_packet_count() > 0:
		var packet = _ws.get_packet()
		_handle_packet(packet)


func _handle_packet(data: PackedByteArray) -> void:
	var text = data.get_string_from_utf8()
	if text.is_empty():
		return
	var json = JSON.new()
	if json.parse(text) != OK:
		print("[NetworkManager] JSON parse error in: '%s'" % text.left(100))
		return
	var msg = json.get_data()
	if typeof(msg) != TYPE_DICTIONARY:
		return
	_dispatch_message(msg)


func _dispatch_message(msg: Dictionary) -> void:
	var msg_type = msg.get("type", "")

	match msg_type:
		"playerJoined":
			player_joined.emit(msg.get("id", ""), msg.get("player", {}))
		"playerLeft":
			player_left.emit(msg.get("id", ""))
		"state":
			_process_state(msg.get("state", msg))
		"patch":
			var patch = msg.get("patch", msg)
			if typeof(patch) == TYPE_DICTIONARY:
				for key in patch:
					game_state[key] = patch[key]
				state_updated.emit(game_state)
		"wave_status":
			var phase = msg.get("phase", "PREP")
			var countdown = float(msg.get("prepTimeRemaining", 0))
			game_phase_updated.emit(phase, countdown)
		"phase":
			var phase = msg.get("phase", "PREP")
			var countdown = float(msg.get("countdown", 0))
			game_phase_updated.emit(phase, countdown)
		"gate_broken", "wave_start", "wave_cleared", "game_over":
			pass  # handled by UI
		"damage":
			damage_received.emit(int(msg.get("amount", 0)))
		"error":
			print("[NetworkManager] Server error: %s" % msg.get("message", "unknown"))
			room_error.emit(msg.get("code", -1), msg.get("message", ""))
		"pickup_result":
			pickup_result.emit(msg.get("success", false), msg.get("itemId", ""))
		"use_item_result":
			use_item_result.emit(msg.get("success", false), msg.get("itemKey", ""))
		"shoot_fx":
			shoot_fx_received.emit(msg)
		"player_hit":
			player_hit_received.emit(msg)
		"zombie_hit":
			zombie_hit_received.emit(msg)
		"zombie_dead":
			zombie_dead_received.emit(msg.get("zombieId", ""))
		"player_dead":
			player_dead_received.emit(msg.get("playerId", ""))
		"no_ammo":
			no_ammo_received.emit()
		_:
			if msg_type != "":
				print("[NetworkManager] Unknown message type: %s" % msg_type)


func _process_state(new_state: Dictionary) -> void:
	game_state = new_state
	state_updated.emit(new_state)
	if new_state.has("players"):
		var players = new_state["players"]
		if typeof(players) == TYPE_DICTIONARY:
			for pid in players:
				player_joined.emit(pid, players[pid])


# ============================================================
# Low-level send
# ============================================================

func _send_msg(data: Dictionary) -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var text = JSON.stringify(data)
	_ws.send(text.to_utf8_buffer(), WebSocketPeer.WRITE_MODE_TEXT)
