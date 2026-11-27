class_name NetLobbyMenu
extends Control
## Online (LAN, experimental) lobby overlay, opened from the main menu when NetConfig.is_enabled().
## Host a server on this PC (127.0.0.1 by default) or join one, set ready, and the race starts once
## NetConfig.MIN_START_READY players are ready. Built in code, plain controls, text through I18n.

const RACE_SCENE: String = "res://race/race_scene.tscn"
const DEFAULT_NAME: String = "Player"

var _address: LineEdit
var _port: LineEdit
var _name: LineEdit
var _ready_btn: Button
var _players: Label
var _status: Label
var _ready_on: bool = false
var _session: NetSession


func _ready() -> void:
	_session = NetSession.get_or_create(get_tree())
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.05, 0.92)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(520, 0)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	box.add_child(_label(I18n.t("net.title"), 26))
	box.add_child(_label(I18n.t("net.local_only"), 14))
	_address = _field(box, I18n.t("net.address"), NetConfig.cmdline_value("address", NetConfig.DEFAULT_BIND))
	_address.text_changed.connect(_on_address_changed)
	_port = _field(box, I18n.t("net.port"), str(NetConfig.DEFAULT_PORT))
	_name = _field(box, I18n.t("net.name"), DEFAULT_NAME)
	var row := HBoxContainer.new()
	row.add_child(_button(I18n.t("net.host"), _on_host))
	row.add_child(_button(I18n.t("net.join"), _on_join))
	_ready_btn = _button(I18n.t("net.ready"), _on_ready)
	row.add_child(_ready_btn)
	row.add_child(_button(I18n.t("net.back"), _on_back))
	box.add_child(row)
	_players = _label(I18n.t("net.no_lobby"), 16)
	box.add_child(_players)
	_status = _label("", 16)
	box.add_child(_status)
	_session.lobby_changed.connect(_on_lobby)
	_session.welcomed.connect(_on_welcomed)
	_session.rejected.connect(_on_rejected)
	_session.connection_lost.connect(_on_lost)
	_session.race_starting.connect(_on_race_starting)
	_session.server_results.connect(_on_server_results)
	if _session.role == NetSession.ROLE_SERVER:
		_status.text = I18n.t("net.hosting_here")
	_refresh_buttons()


func _label(text: String, px: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", px)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _field(parent: Container, caption: String, value: String) -> LineEdit:
	var row := HBoxContainer.new()
	var cap := _label(caption, 16)
	cap.custom_minimum_size = Vector2(90, 0)
	row.add_child(cap)
	var e := LineEdit.new()
	e.text = value
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(e)
	parent.add_child(row)
	return e


func _button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(handler)
	return b


func _refresh_buttons() -> void:
	_ready_btn.visible = _session.role == NetSession.ROLE_CLIENT
	_ready_btn.text = I18n.t("net.not_ready") if _ready_on else I18n.t("net.ready")


func _on_host() -> void:
	var laps: int = int(NetConfig.cmdline_value("laps", "1"))
	var err: String = _session.start_server(_address.text.strip_edges(), int(_port.text), laps, NetConfig.TRACK_SCENE)
	if err != "":
		_status.text = err
		return
	_status.text = I18n.t("net.hosting") % [_address.text, _port.text, laps]
	_refresh_buttons()


## Warns while typing an address the server would refuse to host on (anything but loopback without --address).
func _on_address_changed(text: String) -> void:
	if not NetConfig.bind_allowed(text.strip_edges()) and text.strip_edges() != "":
		_status.text = I18n.t("net.address_warning")


func _on_join() -> void:
	var err: String = _session.connect_to_server(_address.text.strip_edges(), int(_port.text), _name.text)
	if err != "":
		_status.text = err
		return
	_status.text = I18n.t("net.connecting") % [_address.text, _port.text]
	_refresh_buttons()


func _on_ready() -> void:
	_ready_on = not _ready_on
	_session.send_ready(_ready_on)
	_refresh_buttons()


func _on_back() -> void:
	_session.close()
	queue_free()


func _on_lobby(players: Array) -> void:
	var lines: PackedStringArray = PackedStringArray()
	for p: Variant in players:
		var d: Dictionary = p
		lines.append("%s %s" % [I18n.t("net.tag_ready") if bool(d.get("ready", false)) else I18n.t("net.tag_wait"), str(d.get("name", ""))])
	_players.text = I18n.t("net.players") % [players.size(), NetConfig.MAX_PLAYERS, NetConfig.MIN_START_READY] + "\n" + "\n".join(lines)


func _on_welcomed(pid: int) -> void:
	_status.text = I18n.t("net.joined") % pid


func _on_rejected(reason: String) -> void:
	_status.text = I18n.t("net.rejected") % reason
	_ready_on = false
	_refresh_buttons()


func _on_lost(reason: String) -> void:
	_status.text = I18n.t("net.lost") if reason == NetSession.LOST_MESSAGE else reason
	_ready_on = false
	_refresh_buttons()


func _on_server_results(_rows: Array) -> void:
	_status.text = I18n.t("net.race_done")


func _on_race_starting(info: Dictionary) -> void:
	var cfg := RaceConfig.new()
	cfg.net_hold_grid = true
	cfg.opponent_count = 0
	cfg.laps = int(info.get("laps", 1))
	cfg.track_scene = NetConfig.track_for(str(info.get("track", "")))  ## "" = development circuit, the same on every machine
	cfg.autopilot = false
	cfg.traffic_enabled = false
	cfg.event_id = "online_lan"
	call_deferred("_enter_race", cfg)


func _enter_race(cfg: RaceConfig) -> void:
	Router.goto(RACE_SCENE, {"config": cfg})
