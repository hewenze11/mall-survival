extends Node

signal connected
signal disconnected
signal state_updated(state: Dictionary)
signal player_joined(id: String, data: Dictionary)
signal player_left(id: String)
signal phase_changed(phase: String, countdown: float)
signal damage_received(amount: int)

const SERVER_HTTP := "http://104.64.211.23:2567"
const SERVER_WS   := "ws://104.64.211.23:2567"

var local_player_name: String = "Player"
var local_player_id: String = ""
var game_state: Dictionary = {}
var _connected: bool = false

var _ws: WebSocketPeer = null
var _ping_timer: float = 0.0

func join_game(player_name: String) -> void:
	local_player_name = player_name
	_call_join(player_name, "")

func join_room(room_id: String, player_name: String) -> void:
	local_player_name = player_name
	_call_join(player_name, room_id)

func _call_join(player_name: String, room_id: String) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	var body := JSON.stringify({"playerName": player_name, "roomId": room_id})
	http.request_completed.connect(func(r, code, _h, raw):
		http.queue_free()
		_on_join_response(r, code, raw)
	)
	http.request(SERVER_HTTP + "/join", ["Content-Type: application/json"],
		HTTPClient.METHOD_POST, body)

func _on_join_response(result: int, code: int, raw: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		push_error("[NM] Join failed: %d %d" % [result, code])
		disconnected.emit()
		return
	var j := JSON.new()
	if j.parse(raw.get_string_from_utf8()) != OK:
		disconnected.emit()
		return
	var d: Dictionary = j.get_data()
	local_player_id = d.get("sessionId", "")
	var ws_url: String = d.get("wsUrl", "")
	print("[NM] Join OK → %s" % ws_url)
	_connect_ws(ws_url)

func _connect_ws(url: String) -> void:
	_ws = WebSocketPeer.new()
	_ws.connect_to_url(url)

func _process(delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	var state := _ws.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not _connected:
			_connected = true
			print("[NM] Connected!")
			connected.emit()
		while _ws.get_available_packet_count() > 0:
			var raw := _ws.get_packet()
			_handle(raw.get_string_from_utf8())
		_ping_timer += delta
		if _ping_timer >= 5.0:
			_ping_timer = 0.0
			_send({"type": "ping"})

	elif state == WebSocketPeer.STATE_CLOSED and _connected:
		_connected = false
		print("[NM] Disconnected")
		disconnected.emit()
		_ws = null

func _handle(text: String) -> void:
	var j := JSON.new()
	if j.parse(text) != OK:
		return
	var msg: Dictionary = j.get_data()
	match msg.get("type", ""):
		"state":
			game_state = msg.get("state", {})
			state_updated.emit(game_state)
		"playerJoined":
			player_joined.emit(msg.get("id",""), msg.get("data",{}))
		"playerLeft":
			player_left.emit(msg.get("id",""))
		"phaseChange":
			phase_changed.emit(msg.get("phase",""), float(msg.get("countdown", 0)))
		"playerHit":
			if msg.get("playerId","") == local_player_id:
				damage_received.emit(int(msg.get("amount",0)))

func _send(data: Dictionary) -> void:
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(data))

func send_move(x: float, y: float, dir: String) -> void:
	_send({"type":"move","x":x,"y":y,"dir":dir})

func send_shoot(tx: float, ty: float) -> void:
	_send({"type":"shoot","targetX":tx,"targetY":ty})

func send_pickup(item_id: String) -> void:
	_send({"type":"pickup","itemId":item_id})

func is_connected_to_room() -> bool:
	return _connected
