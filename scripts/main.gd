extends Control

const S := preload("res://scripts/sim.gd")
const Challenge := preload("res://scripts/challenge_sim.gd")
const Board := preload("res://scripts/board.gd")
const Store := preload("res://scripts/save_store.gd")
const Audio := preload("res://scripts/game_audio.gd")
const UI_FONT := preload("res://assets/interface_font.tres")
const BG := Color("#11262a")
const PANEL := Color("#1c3538")
const PANEL_LIGHT := Color("#274347")
const BORDER := Color("#48635f")
const TEXT := Color("#f3edda")
const MUTED := Color("#abc2b3")
const GOLD := Color("#efb873")
const TEAL := Color("#95d3bb")
const RED := Color("#ffad88")

var sim = S.new()
var store = Store.new()
var progress: Dictionary = {}
var state: Dictionary = {}
var undo_stack: Array[Dictionary] = []
var actions_this_turn := 0
var page := "home"
var modal_kind := ""
var selected_tool := "shovel"
var forecast_enabled := true
var resolving := false
var message := ""
var message_time := 0.0
var reduced_motion := false
var buttons: Dictionary = {}
var font: Font
var audio
var content: VBoxContainer
var header: HBoxContainer
var modal_layer: Control
var modal_box: VBoxContainer
var board
var labels: Dictionary = {}
var status_label: Label
var total_time := 0.0
var turn_lock_time := 0.0
var session_path_override := ""
var hint_shown := false
var hint_expanded := false
var auto_waiting := false
var auto_wait_time := 0.0
var safe_wait_turns := 0
var game_mode := "campaign"
var challenge_root := 1
var challenge_sector := 1
var challenge_score := 0
var challenge_completed := 0
var inspect_mode := false
var mobile_layout := false
var last_share_text := ""
var result_recorded := false
var safe_finish_turns := -1
var intro_scene := 0
var shell_outer: MarginContainer
var shell_layout: VBoxContainer
var resize_pending := false
var modal_scroll: ScrollContainer
var modal_natural_height := 0.0

func _ready() -> void:
	font = UI_FONT
	_build_theme()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--save-path="):
			session_path_override = arg.trim_prefix("--save-path=")
	if not session_path_override.is_empty():
		store.path = session_path_override
	progress = store.load_progress()
	mobile_layout = OS.has_feature("mobile")
	var session: Variant = progress.get("session", {})
	if str(progress.get("active_mode", "campaign")) == "challenge":
		_restore_challenge(progress.get("challenge_session", {}))
		if state.is_empty():
			progress["challenge_session"] = {}
			progress["active_mode"] = "campaign"
	if state.is_empty() and session is Dictionary and not session.is_empty():
		state = sim.deserialize_state(session)
		if state.is_empty() or str(state.get("status", "")) != "playing":
			state = {}
			progress["session"] = {}
	reduced_motion = bool(progress["reduced_motion"])
	audio = Audio.new()
	add_child(audio)
	audio.set_muted(bool(progress["muted"]))
	get_tree().auto_accept_quit = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_shell()
	mobile_layout = _compact_window()
	_apply_viewport_scale()
	_build_theme()
	_show_home()
	get_viewport().size_changed.connect(_schedule_layout)
	if not store.last_error.is_empty():
		_notify(store.last_error, true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_persist()
		get_tree().quit()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if not modal_kind.is_empty():
			_close_modal()
		elif page == "game":
			_show_pause()
		else:
			_show_home()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		_persist()

func _process(delta: float) -> void:
	total_time += delta
	if message_time > 0:
		message_time -= delta
		if message_time <= 0 and is_instance_valid(status_label):
			status_label.text = "每一步都能预判。布防完成后，再让风推动火线。" if page == "game" else "离线游玩 · 自动保存 · 无需账号"
	if resolving:
		turn_lock_time -= delta
		if turn_lock_time <= 0:
			resolving = false
			if page == "game":
				_update_game()
	if auto_waiting:
		if page != "game" or not modal_kind.is_empty() or state.get("status") != "playing":
			auto_waiting = false
		elif not resolving:
			auto_wait_time -= delta
			if auto_wait_time <= 0:
				if _safe_finish_turns() < 0:
					auto_waiting = false
					_update_game()
					_notify("风向或湿润状态仍有变化，请继续布防。")
				else:
					auto_wait_time = .5
					_end_turn()
	elif not hint_shown and page == "game" and modal_kind.is_empty() and state.get("status") == "playing" and int(state.get("turn", 1)) >= 2 and safe_finish_turns >= 0:
		hint_shown = true
		_notify("防线已守住。可点「等待余火」看火自然烧尽，也可继续逐轮观察。", false)
	if is_instance_valid(board):
		board.reduced_motion = reduced_motion
		board.high_contrast = bool(progress["high_contrast"])
		board.interactive = page == "game" and modal_kind.is_empty() and not resolving and not auto_waiting and state.get("status") == "playing"
	audio.set_fire_intensity(sim.burning_count(state) if page == "game" and modal_kind.is_empty() and not state.is_empty() else 0)

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F11:
		_toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_M:
		_toggle_mute()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_ESCAPE:
		if auto_waiting:
			auto_waiting = false
			_update_game()
			_notify("已停下等待，可以继续布防。")
		elif not modal_kind.is_empty():
			if modal_kind == "result":
				_show_levels()
			else:
				_close_modal()
		elif page == "game":
			_show_pause()
		elif page != "home":
			_show_home()
		get_viewport().set_input_as_handled()
		return
	if page != "game" or not modal_kind.is_empty() or state.get("status") != "playing" or resolving:
		return
	if auto_waiting:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			auto_waiting = false
			_update_game()
		get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_1: _select_tool("shovel")
		KEY_2: _select_tool("axe")
		KEY_3: _select_tool("water")
		KEY_Z: _undo()
		KEY_R: _confirm_restart()
		KEY_P: _toggle_forecast()
		KEY_I: _toggle_inspect()
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER: _end_turn()
		_: return
	get_viewport().set_input_as_handled()

func _build_theme() -> void:
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 16
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color("#fff9ec"))
	t.set_color("font_pressed_color", "Button", Color("#ffffff"))
	t.set_color("font_disabled_color", "Button", Color("#708f88"))
	t.set_constant("outline_size", "Button", 0)
	t.set_stylebox("normal", "Button", _style(PANEL_LIGHT, BORDER, 9))
	t.set_stylebox("hover", "Button", _style(Color("#3b5758"), TEAL, 9))
	t.set_stylebox("pressed", "Button", _style(Color("#536252"), GOLD, 9))
	t.set_stylebox("disabled", "Button", _style(Color("#192e32"), Color("#304c4b"), 9))
	var focus := _style(Color(0,0,0,0), GOLD, 9)
	focus.set_border_width_all(2)
	t.set_stylebox("focus", "Button", focus)
	t.set_constant("separation", "VBoxContainer", 12)
	t.set_constant("separation", "HBoxContainer", 12)
	t.set_constant("separation", "HFlowContainer", 10)
	theme = t

func _style(color: Color, border: Color, radius: int = 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 12 if mobile_layout else 18
	s.content_margin_right = 12 if mobile_layout else 18
	s.content_margin_top = 8 if mobile_layout else 12
	s.content_margin_bottom = 8 if mobile_layout else 12
	return s

func _build_shell() -> void:
	var background := ColorRect.new()
	background.color = BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var outer := MarginContainer.new()
	shell_outer = outer
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("margin_left", 30)
	outer.add_theme_constant_override("margin_right", 30)
	outer.add_theme_constant_override("margin_top", 22)
	outer.add_theme_constant_override("margin_bottom", 18)
	add_child(outer)
	var layout := VBoxContainer.new()
	shell_layout = layout
	layout.add_theme_constant_override("separation", 16)
	outer.add_child(layout)
	header = HBoxContainer.new()
	header.custom_minimum_size.y = 48
	layout.add_child(header)
	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(content)
	status_label = _label("离线游玩 · 自动保存 · 无需账号", 13, MUTED)
	status_label.name = "Status"
	layout.add_child(status_label)
	modal_layer = Control.new()
	modal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_layer.visible = false
	modal_layer.z_index = 10
	add_child(modal_layer)

func _clear(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _new_page(which: String) -> void:
	_close_modal()
	page = which
	auto_waiting = false
	buttons.clear()
	labels.clear()
	board = null
	_clear(content)
	_clear(header)
	message_time = 0.0
	shell_outer.add_theme_constant_override("margin_left", 18 if mobile_layout else 30)
	shell_outer.add_theme_constant_override("margin_right", 18 if mobile_layout else 30)
	shell_outer.add_theme_constant_override("margin_top", 10 if mobile_layout else 22)
	shell_outer.add_theme_constant_override("margin_bottom", 10 if mobile_layout else 18)
	shell_layout.add_theme_constant_override("separation", 8 if mobile_layout else 16)
	header.custom_minimum_size.y = 44 if mobile_layout else 48
	status_label.add_theme_font_size_override("font_size", 12 if mobile_layout else 13)
	status_label.text = "每一步都能预判。布防完成后，再让风推动火线。" if which == "game" else "离线游玩 · 自动保存 · 无需账号"
	var brand := HBoxContainer.new()
	var mark := _label("///", 25, GOLD)
	brand.add_child(mark)
	brand.add_child(_label("燎原", 26))
	var caption := _label("山火布防行动", 13, MUTED)
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	brand.add_child(caption)
	header.add_child(brand)
	_spacer(header)
	if which == "game":
		_button(header,"规则", "header_rules", _show_rules, false, 68)
		_button(header,"暂停  Esc", "pause", _show_pause, false, 108)
	elif which != "home":
		_button(header,"返回主界面", "home", _show_home, false, 128)
	_button(header, "声音：关" if progress["muted"] else "声音：开", "mute", _toggle_mute, false, 98)
	_button(header, "设置", "settings", _show_settings, false, 68)

func _show_home() -> void:
	if state.get("status") == "playing":
		_persist()
	_new_page("home")
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24 if mobile_layout else 40)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 370 if mobile_layout else 400
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8 if mobile_layout else 12)
	columns.add_child(left)
	_spacer(left, true)
	left.add_child(_label("FIELD NOTES   /   01", 14, GOLD))
	left.add_child(_label("守住村庄。\n让火无路可走。", 31 if mobile_layout else 40))
	var intro := _label("火不听你指挥。\n但它脚下的草地、树林与水汽，可以。", 16 if mobile_layout else 19, MUTED)
	left.add_child(intro)
	var note := _wrap("一款关于「涌现」的回合制策略游戏。\n观察下一轮火线，布防，然后见证规则自己演化。", 13 if mobile_layout else 15, MUTED)
	note.custom_minimum_size.y = 48 if mobile_layout else 64
	left.add_child(note)
	if state.get("status") == "playing":
		_button(left,"继续上次布防", "continue", _resume_game, true)
	else:
		_button(left,"开始守林", "start", _start_recommended, true)
	var row := HBoxContainer.new()
	left.add_child(row)
	_button(row,"五处林地", "levels", _show_levels)
	_button(row,"怎么玩", "rules", _show_rules)
	_button(left,"巡护挑战 · 每次一片新林地", "challenge", _request_challenge)
	if int(progress.get("challenge_best", 0)) > 0:
		left.add_child(_label("巡护纪录  %d 分 · %d 片林地" % [progress["challenge_best"],progress["challenge_best_sectors"]], 13, TEAL))
	_button(left,"退出游戏", "quit", _quit, false)
	_spacer(left, true)
	left.add_child(_label("5 个手作关卡  ·  可重复的编号巡护\n可撤销布防  ·  无时间压力  ·  原生 Godot 客户端", 13, MUTED))
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	var caption_row := HBoxContainer.new()
	right.add_child(caption_row)
	caption_row.add_child(_label("山林态势图", 17, TEAL))
	_spacer(caption_row)
	caption_row.add_child(_label("可见的规则 / 不写死的火线", 12, MUTED))
	board = Board.new()
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.custom_minimum_size = Vector2(460, 270) if mobile_layout else Vector2(580, 440)
	right.add_child(board)
	var demo_sim = S.new()
	var demo: Dictionary = demo_sim.new_game(0, int(S.LEVELS[0].get("seed", 1)))
	demo_sim.end_turn(demo)
	demo_sim.end_turn(demo)
	board.present(demo, demo_sim.forecast_next(demo))
	board.interactive = false
	board.reduced_motion = reduced_motion
	var below := _panel_vbox(right)
	below.add_child(_label("一步布局，整片森林回应。", 20))
	below.add_child(_label("火绕开断带；多处热量汇聚；湿地撑住最后三轮。\n不是拼手速，而是读懂它将怎样发生。", 14, MUTED))
	var footer := HBoxContainer.new()
	content.add_child(footer)
	footer.add_child(_label("EMERGENCE / 涌现", 12, GOLD))
	_spacer(footer)
	footer.add_child(_label("F11 全屏", 12, MUTED))
	_focus("continue" if state.get("status") == "playing" else "start")

func _show_levels() -> void:
	_persist()
	_new_page("levels")
	content.add_child(_label("选择一片值得守护的林地", 30))
	content.add_child(_label("每关先读风，再动土。星级不会倒退；你随时可以回来换一种解法。", 16, MUTED))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(grid)
	for i: int in range(S.LEVELS.size()):
		var level: Dictionary = S.LEVELS[i]
		var card := _panel_vbox(grid)
		card.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.get_parent().custom_minimum_size = Vector2(320, 166) if mobile_layout else Vector2(345, 228)
		card.add_child(_label("0%d / %s" % [i + 1, level["name"]], 23, TEXT))
		var stars: int = int(progress["stars"].get(str(i), 0))
		card.add_child(_label("★".repeat(stars) + "☆".repeat(3 - stars), 21, GOLD))
		card.add_child(_wrap(str(level.get("brief", level["goal"])), 15, MUTED))
		_spacer(card, true)
		var locked: bool = i > int(progress["unlocked"])
		var b := _button(card,"先守住上一片林地" if locked else "前往布防", "level_%d" % i, _request_level.bind(i), not locked)
		b.disabled = locked
		if progress["best"].has(str(i)):
			var best: Dictionary = progress["best"][str(i)]
			card.add_child(_label("最佳保留 %d%% · %d 回合" % [roundi(float(best["saved"]) * 100), best["turns"]], 13, MUTED))
	var last := _panel_vbox(grid)
	last.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	last.add_child(_label("做得更少，留下更多。", 21, TEAL))
	last.add_child(_wrap("★★★ 保留至少 70% 植被，并在目标回合内结束。\n★★ 保留至少 45% 植被。\n★ 保住全部房屋。\n\n砍掉或铲除的植被也计入损失。", 15, MUTED))
	_focus("level_0")

func _start_recommended() -> void:
	_start_level(clampi(int(progress["unlocked"]), 0, S.LEVELS.size() - 1))

func _request_level(index: int) -> void:
	if state.get("status") == "playing":
		_open_modal("new_game", "开始另一处布防？", "上一局会被替换。已获得的星级会保留。")
		_modal_button("保留当前局", "cancel", _close_modal)
		_modal_button("开始这一关", "confirm_level", _start_level.bind(index), true)
	else:
		_start_level(index)

func _start_level(index: int) -> void:
	game_mode = "campaign"
	sim = S.new()
	var level: Dictionary = S.LEVELS[clampi(index, 0, S.LEVELS.size()-1)]
	state = sim.new_game(index, int(level.get("seed", 1)))
	undo_stack.clear()
	result_recorded = false
	actions_this_turn = 0
	selected_tool = "shovel"
	inspect_mode = false
	hint_shown = false
	safe_wait_turns = 0
	forecast_enabled = true
	resolving = false
	_build_game()
	var welcome := "先看风向和橙框。需要思路时，右侧可以展开提示。"
	if index == 0:
		welcome = "第一关只需挖出一条短防线。铁锹已选好，点击草地试试。"
	_notify(welcome)
	_persist()

func _resume_game() -> void:
	if state.get("status") != "playing":
		_start_recommended()
		return
	undo_stack.clear()
	resolving = false
	_build_game()
	_notify("已恢复上次的布防。火不会自行推进，准备好后再结束回合。")

func _current_level() -> Dictionary:
	return sim.level_info(state)

func _compact_window() -> bool:
	return OS.has_feature("mobile") or get_window().size.y < 700

func _apply_viewport_scale() -> void:
	var target := Vector2i(1200, 600) if mobile_layout else Vector2i(1200, 820)
	if get_window().content_scale_size != target:
		get_window().content_scale_size = target

func _schedule_layout() -> void:
	if is_instance_valid(modal_scroll) and modal_layer.visible:
		modal_scroll.custom_minimum_size.y = minf(modal_natural_height, get_viewport_rect().size.y - 32)
	if not resize_pending:
		resize_pending = true
		_rebuild_layout.call_deferred()

func _rebuild_layout() -> void:
	resize_pending = false
	var compact: bool = _compact_window()
	if compact == mobile_layout or not modal_kind.is_empty():
		return
	mobile_layout = compact
	_apply_viewport_scale()
	_build_theme()
	match page:
		"game": _build_game()
		"levels": _show_levels()
		_: _show_home()

func _request_challenge() -> void:
	_open_modal("challenge_setup", "沿着河岸，继续巡护。", "每片林地按编号生成；规则不变，桥口、树林和风序会变。相同编号可以反复挑战，也能发给朋友。")
	modal_box.add_child(_wrap("难度前三片逐步提升，之后保持最高难度。保留的植被越多，巡护分越高；任何房屋起火，巡护结束。没有在线排行。", 15, MUTED))
	var input := LineEdit.new()
	input.name = "ChallengeSeed"
	input.placeholder_text = "巡护编号：1—99999999（留空自动生成）"
	input.max_length = 8
	input.custom_minimum_size.y = 44
	modal_box.add_child(input)
	_modal_button("开始编号巡护", "challenge_start", func() -> void:
		var text := input.text.strip_edges()
		if not text.is_empty() and (not text.is_valid_int() or int(text) < 1):
			_notify("请输入 1—99999999 的整数编号。", true)
			return
		var chosen: int = int(text) if not text.is_empty() else int(Time.get_unix_time_from_system()) % 99999999 + 1
		_start_challenge(chosen)
	, true)
	_modal_button("先回林地", "cancel_challenge", _close_modal)

func _start_challenge(root_seed: int, sector: int = 1, score: int = 0, completed: int = 0) -> void:
	if game_mode == "campaign" and state.get("status") == "playing":
		progress["session"] = sim.serialize_state(state)
	game_mode = "challenge"
	sim = Challenge.new()
	challenge_root = clampi(root_seed, 1, 99999999)
	challenge_sector = maxi(1, sector)
	challenge_score = maxi(0, score)
	challenge_completed = maxi(0, completed)
	state = sim.new_challenge(sim.seed_for_sector(challenge_root, challenge_sector))
	undo_stack.clear()
	result_recorded = false
	actions_this_turn = 0
	inspect_mode = false
	selected_tool = "shovel"
	resolving = false
	hint_shown = false
	forecast_enabled = true
	_build_game()
	_notify("巡护 #%d · 第 %d 片。桥口与树林已变，但火仍遵守同一套规则。" % [challenge_root,challenge_sector])
	_persist()

func _next_challenge() -> void:
	_start_challenge(challenge_root, challenge_sector + 1, challenge_score, challenge_completed)

func _retry_current() -> void:
	if game_mode == "challenge":
		_start_challenge(challenge_root)
	else:
		_start_level(int(state["level"]))

func _restore_challenge(envelope: Variant) -> void:
	if not envelope is Dictionary:
		return
	for key: String in ["root", "sector", "score", "completed"]:
		var value: Variant = envelope.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or floorf(float(value)) != float(value) or float(value) < 0 or float(value) > 100000000:
			return
	if int(envelope["root"]) < 1 or int(envelope["root"]) > 99999999 or int(envelope["sector"]) < 1:
		return
	var candidate = Challenge.new()
	var restored: Dictionary = candidate.deserialize_state(envelope.get("state"))
	if restored.is_empty() or restored["status"] != "playing" or int(restored["seed"]) != candidate.seed_for_sector(int(envelope["root"]), int(envelope["sector"])):
		return
	if int(envelope["completed"]) != int(envelope["sector"]) - 1:
		return
	sim = candidate
	state = restored
	game_mode = "challenge"
	challenge_root = int(envelope["root"])
	challenge_sector = int(envelope["sector"])
	challenge_score = int(envelope["score"])
	challenge_completed = int(envelope["completed"])

func _build_game() -> void:
	_new_page("game")
	var level: Dictionary = _current_level()
	var metrics := HBoxContainer.new()
	metrics.add_theme_constant_override("separation", 14)
	content.add_child(metrics)
	_metric(metrics, "巡护编号 / 得分" if game_mode == "challenge" else "当前林地", "#%d · %d 分" % [challenge_root,challenge_score] if game_mode == "challenge" else "0%d  /  %s" % [int(state["level"])+1, level["name"]], "level_name", 20 if mobile_layout else 26)
	_metric(metrics, "布防回合", "", "turn", 23)
	_metric(metrics, "本轮行动", "", "ap", 23)
	_metric(metrics, "守护房屋", "", "houses", 23)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)
	var board_column := VBoxContainer.new()
	board_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(board_column)
	board = Board.new()
	board.name = "Board"
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.custom_minimum_size = Vector2(600, 275) if mobile_layout else Vector2(765, 445)
	board_column.add_child(board)
	board.cell_chosen.connect(_choose_cell)
	board.cell_hovered.connect(_inspect_cell)
	var legend := HBoxContainer.new()
	board_column.add_child(legend)
	legend.add_child(_label("! 下一轮起火", 13, GOLD))
	legend.add_child(_label("蓝框：防火轮数", 13, Color("#9fdcde")))
	_spacer(legend)
	var inspect_button := _button(legend, "查看 / 施工  I", "inspect", _toggle_inspect, false, 130, 38)
	inspect_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	var forecast_button := _button(legend,"预判：开  P", "forecast", _toggle_forecast, false, 110, 38)
	forecast_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	var side := _game_sidebar(body)
	side.add_theme_constant_override("separation", 6 if mobile_layout else 10)
	side.get_parent().custom_minimum_size.x = 302
	side.add_child(_label("先读风，再动土。", 18 if mobile_layout else 21, GOLD))
	labels["wind"] = _label("", 22)
	side.add_child(labels["wind"])
	labels["future"] = _label("", 14, MUTED)
	side.add_child(labels["future"])
	_separator(side)
	labels["forecast"] = _wrap("", 15, GOLD)
	side.add_child(labels["forecast"])
	labels["lesson"] = _wrap(str(level.get("tip", level["goal"])), 14 if mobile_layout else 15, TEXT)
	labels["lesson"].custom_minimum_size.y = 42 if mobile_layout else 70
	side.add_child(labels["lesson"])
	if not mobile_layout:
		_button(side,"提示：展开", "hint", _toggle_hint, false, 0, 34)
	_separator(side)
	labels["detail_name"] = _label("观察一格", 18, TEAL)
	labels["detail"] = _wrap("把鼠标移到地图上，查看热量、剩余燃烧时间和工具是否可用。", 14, MUTED)
	labels["detail"].custom_minimum_size.y = 70 if mobile_layout else 96
	side.add_child(labels["detail_name"])
	side.add_child(labels["detail"])
	_spacer(side, true)
	labels["score"] = _label("", 12 if mobile_layout else 13, MUTED)
	side.add_child(labels["score"])
	_button(side,"等待余火", "wait", _toggle_wait, false, 0, 38)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	content.add_child(actions)
	_button(actions,"1  铁锹\n草地 / 灌木 → 防火带", "tool_shovel", _select_tool.bind("shovel"), false, 205 if mobile_layout else 225, 58 if mobile_layout else 66)
	_button(actions,"2  斧头\n树木 → 草地", "tool_axe", _select_tool.bind("axe"), false, 182 if mobile_layout else 202, 58 if mobile_layout else 66)
	_button(actions,"3  水壶\n清热 / 防火 3 轮", "tool_water", _select_tool.bind("water"), false, 182 if mobile_layout else 202, 58 if mobile_layout else 66)
	_spacer(actions)
	_button(actions,"撤销  Z", "undo", _undo, false, 110 if mobile_layout else 116, 58 if mobile_layout else 66)
	_button(actions,"结束回合  Space", "end", _end_turn, true, 195 if mobile_layout else 216, 58 if mobile_layout else 66)
	_update_game()

func _update_game() -> void:
	if page != "game" or state.is_empty() or not is_instance_valid(board):
		return
	var prediction: Dictionary = sim.forecast_next(state)
	board.present(state, prediction)
	board.selected_tool = selected_tool
	board.inspect_only = inspect_mode
	board.show_forecast = forecast_enabled
	board.tutorial_cells.clear()
	if game_mode == "campaign" and int(state["level"]) == 0 and not bool(progress["tutorial_done"]):
		for cell: Vector2i in [Vector2i(5,3),Vector2i(5,4),Vector2i(5,5)]:
			if state["cells"][sim.cell_index(cell.x,cell.y)]["tile"] != S.FIREBREAK:
				board.tutorial_cells.append(cell)
	labels["turn"].text = "%02d" % int(state["turn"])
	labels["ap"].text = "%d / %d  AP" % [state["ap"], state["ap_max"]]
	labels["ap"].modulate = TEAL if int(state["ap"]) > 0 else GOLD
	labels["houses"].text = "%d / %d" % [state["hut_alive"], state["huts"]]
	labels["wind"].text = "本次风向  " + S.DIR_CH[int(state["wind"])] + "  " + _wind_text(int(state["wind"]))
	var future: Array[String] = []
	for w: Variant in state["forecast"]:
		future.append(S.DIR_CH[int(w)])
	labels["future"].text = "之后三轮   " + "    ".join(future)
	var imminent: int = prediction.get("ignited", []).size()
	var threatened: int = prediction.get("threatened_huts", []).size()
	if not forecast_enabled:
		labels["forecast"].text = "预判已隐藏\n按 P 恢复火势标记。"
	elif threatened > 0:
		labels["forecast"].text = "本次推进会烧到 %d 处房屋！\n先用水保护房屋，或切断热源。" % threatened
	elif imminent > 0:
		labels["forecast"].text = "下一轮：%d 格将起火\n橙框会随你的每次布防更新。" % imminent
	else:
		labels["forecast"].text = "下一轮：没有新增火点\n余火仍可能在之后继续积热。"
	labels["forecast"].modulate = RED if threatened > 0 else Color.WHITE
	labels["lesson"].text = _lesson()
	var result: Dictionary = sim.stats(state)
	labels["score"].text = "保留 %d%% · 巡护第 %d 片" % [roundi(float(result["saved_fraction"])*100),challenge_sector] if game_mode == "challenge" else "植被保留  %d%%\n三星：保留 ≥70%% 且 ≤%d 轮" % [roundi(float(result["saved_fraction"])*100), int(_current_level()["par"])]
	var playing: bool = str(state["status"]) == "playing" and not resolving and not auto_waiting
	safe_finish_turns = _safe_finish_turns()
	buttons["wait"].text = "停下等待" if auto_waiting else ("等待余火 · 还需 %d 轮" % safe_finish_turns if safe_finish_turns >= 0 else "仍需布防 · 暂不可快进")
	buttons["wait"].disabled = not auto_waiting and (safe_finish_turns < 0 or resolving or state["status"] != "playing")
	for key: String in ["shovel", "axe", "water"]:
		var b: Button = buttons["tool_"+key]
		b.add_theme_stylebox_override("normal", _style(Color("#3c5346") if key == selected_tool else PANEL_LIGHT, GOLD if key == selected_tool else BORDER, 9))
		b.disabled = not playing
	buttons["undo"].disabled = undo_stack.is_empty() or not playing
	buttons["end"].disabled = not playing
	buttons["end"].text = "正在推进…" if resolving else "结束回合  Space"
	buttons["forecast"].text = "预判：开  P" if forecast_enabled else "预判：关  P"
	buttons["inspect"].text = "查看中 · 不耗 AP" if inspect_mode else "施工中 · 点格布防"
	buttons["inspect"].add_theme_color_override("font_color", TEAL if inspect_mode else TEXT)
	if buttons.has("hint"):
		buttons["hint"].text = "提示：收起" if hint_expanded else "提示：展开"
	_inspect_cell(board.hover_cell)

func _lesson() -> String:
	if inspect_mode:
		return "查看模式\n点格子只看详情，不会施工或消耗行动点。选工具即可切回施工。"
	if game_mode == "campaign" and int(state["level"]) == 0 and not bool(progress["tutorial_done"]):
		if int(state["turn"]) == 1 and actions_this_turn == 0:
			return "第一步\n沿浅绿框挖 F4、F5、F6，接成一条三格防线。每格 1 AP。"
		if int(state["turn"]) == 1:
			return "第二步\n继续补齐浅绿框，连到上下水岸。完成后点结束回合；Z 可以撤销。"
		if safe_finish_turns >= 0:
			return "第三步\n防线已稳固。点等待余火，见证简单规则如何改变整片火线。"
		return "留意斜角\n火向相邻八格供热。蓝框数字是还能防火的完整轮数。"
	return str(_current_level().get("tip", "保护全部房屋，直到最后一点火烧尽。")) if hint_expanded or mobile_layout or game_mode == "challenge" else str(_current_level()["goal"])

func _toggle_hint() -> void:
	hint_expanded = not hint_expanded
	_update_game()

func _toggle_inspect() -> void:
	if page != "game" or not modal_kind.is_empty() or resolving or auto_waiting:
		return
	inspect_mode = not inspect_mode
	_update_game()
	_notify("查看模式：点格子看热量和预报，不会消耗 AP。" if inspect_mode else "施工模式：点格子使用当前工具。")

func _choose_cell(cell: Vector2i) -> void:
	if inspect_mode:
		_inspect_cell(cell)
	else:
		_apply_cell(cell)

func _safe_finish_turns() -> int:
	if state.get("status") != "playing":
		return -1
	var preview_state: Dictionary = sim.clone_state(state)
	for turns: int in range(1, 41):
		var event: Dictionary = sim.end_turn(preview_state)
		if event.get("hut_lost", false):
			return -1
		if preview_state["status"] == "won":
			return turns
	return -1

func _toggle_wait() -> void:
	if auto_waiting:
		auto_waiting = false
		_update_game()
		return
	if _safe_finish_turns() < 0 or resolving or not modal_kind.is_empty():
		return
	auto_waiting = true
	auto_wait_time = .6
	_update_game()
	_notify("正在等待余火。每轮仍按原规则演化；空格或 Esc 随时停下。")

func _inspect_cell(cell: Vector2i) -> void:
	if page != "game" or not labels.has("detail"):
		return
	if cell.x < 0 or not sim.in_bounds(cell.x, cell.y):
		labels["detail_name"].text = "观察一格"
		labels["detail"].text = "点「查看」后可安全观察格子。\n每种工具消耗 1 AP。\n选工具切回施工，按 Z 撤销。"
		return
	var index: int = sim.cell_index(cell.x, cell.y)
	var current: Dictionary = state["cells"][index]
	labels["detail_name"].text = "%s%d  ·  %s" % [String.chr(65+cell.x), cell.y+1, S.TILE_NAMES[int(current["tile"])]]
	var lines: Array[String] = []
	if int(current["burn"]) > 0:
		lines.append("正在燃烧，还会传播 %d 轮。" % current["burn"])
		lines.append("无法在火中直接施工。")
	elif int(current["threshold"]) == 0:
		lines.append("不燃地形，火不能直接跳过。")
	else:
		lines.append("热量 %d / %d" % [current["heat"],current["threshold"]])
		if int(current["wet"]) > 0:
			lines.append("还可完整防火 %d 轮。" % current["wet"])
		if forecast_enabled:
			if board.forecast.get("ignited",[]).has(index):
				lines.append("! 下一轮将起火。")
			else:
				var heat: Array = board.forecast.get("heat", [])
				if index < heat.size():
					lines.append("下一轮热量 %d。" % int(heat[index]))
	var check: Dictionary = sim.can_apply(state, cell.x, cell.y, selected_tool)
	board.hover_valid = inspect_mode or bool(check["ok"])
	lines.append("查看中，不消耗行动点。" if inspect_mode else ("点击使用%s · 1 AP" % S.TOOL_NAMES[selected_tool] if check["ok"] else str(check.get("why", "这里不能使用这个工具"))))
	labels["detail"].text = "\n".join(lines)

func _select_tool(tool: String) -> void:
	if page != "game" or not modal_kind.is_empty() or resolving:
		return
	selected_tool = tool
	inspect_mode = false
	audio.play_cue("select")
	_update_game()

func _apply_cell(cell: Vector2i) -> void:
	if page != "game" or not modal_kind.is_empty() or resolving or auto_waiting or state.get("status") != "playing":
		return
	var before: Dictionary = sim.clone_state(state)
	var result: Dictionary = sim.apply_tool(state, cell.x, cell.y, selected_tool)
	if result["ok"]:
		undo_stack.append(before)
		actions_this_turn += 1
		audio.play_cue({"shovel":"dig", "axe":"axe", "water":"water"}[selected_tool])
		_update_game()
		_persist()
		_notify("%s%d · %s完成。%s" % [String.chr(65+cell.x),cell.y+1,S.TOOL_NAMES[selected_tool], "行动已用完，准备结束回合。" if int(state["ap"]) == 0 else "可以继续布防或按 Z 撤销。"])
		auto_waiting = false
		safe_wait_turns = 0
	else:
		_notify(str(result.get("why", "无法使用")), true)

func _undo() -> void:
	if undo_stack.is_empty() or state.get("status") != "playing" or resolving:
		return
	state = undo_stack.pop_back()
	actions_this_turn = maxi(0, actions_this_turn - 1)
	audio.play_cue("undo")
	_update_game()
	_persist()
	_notify("已撤销这一步，行动点已返还。")

func _end_turn() -> void:
	if page != "game" or not modal_kind.is_empty() or resolving or state.get("status") != "playing":
		return
	var event: Dictionary = sim.end_turn(state)
	undo_stack.clear()
	result_recorded = false
	actions_this_turn = 0
	board.show_transition(event)
	audio.play_cue("wind" if event.get("wind_changed", false) else "turn")
	resolving = true
	turn_lock_time = .3 if not reduced_motion else .08
	_update_game()
	if state["status"] != "playing":
		resolving = false
		auto_waiting = false
		_finish_game()
	else:
		_persist()
		_notify("火线推进：新增 %d 格起火。" % event.get("ignited",[]).size())

func _finish_game() -> void:
	var result: Dictionary = sim.stats(state)
	var won: bool = state["status"] == "won"
	if game_mode == "challenge":
		if won and not result_recorded:
			challenge_completed += 1
			challenge_score += int(result["saved_value"]) * 10 + int(result["stars"]) * 100 + maxi(0, int(_current_level()["par"]) - int(result["turn"])) * 5
		store.record_challenge(progress, challenge_score, challenge_completed)
		progress["challenge_session"] = {}
	elif won:
		store.record_win(progress, int(state["level"]), result)
	else:
		progress["session"] = {}
	result_recorded = true
	_persist()
	var index: int = int(state["level"])
	var title := "这片林地，守住了。" if won else "防线被突破了。"
	var subtitle := "村庄安然无恙。你改变了地形，火就改变了去路。" if won else "不是拼运气。看清下一轮橙框，再改一条防火带。"
	if game_mode == "challenge":
		title = "巡护第 %d 片，守住了。" % challenge_sector if won else "巡护到这里，留下了记录。"
		subtitle = "编号 #%d · 累计 %d 分 · 守住 %d 片林地" % [challenge_root,challenge_score,challenge_completed]
	elif won and index == S.LEVELS.size()-1:
		title = "五处林地，全部守住。"
		subtitle = "从一条断带到多线布局，你已经读懂了火的规则。"
	_open_modal("result", title, subtitle)
	if won:
		modal_box.add_child(_label("★".repeat(int(result["stars"])) + "☆".repeat(3-int(result["stars"])), 32 if mobile_layout else 38, GOLD, true))
	var summary := _label("%d 回合  /  植被保留 %d%%  /  房屋 %d / %d" % [result["turn"],roundi(float(result["saved_fraction"])*100),state["hut_alive"],state["huts"]], 17, TEXT, true)
	summary.name = "ResultStats"
	modal_box.add_child(summary)
	modal_box.add_child(_wrap("三星：保留 ≥70%% 且 ≤%d 回合。砍伐与挖带也计入损失。" % int(_current_level()["par"]), 14, MUTED))
	if not won:
		modal_box.add_child(_wrap("提示：" + str(_current_level()["tip"]), 14, GOLD))
	if game_mode == "challenge":
		if won:
			_modal_button("下一片巡护林地", "challenge_next", _next_challenge, true)
		_modal_button("重新挑战这个编号", "retry", _retry_current)
		_modal_button("返回主界面", "result_home", _show_home)
	elif won and index < S.LEVELS.size()-1:
		_modal_button("下一片林地", "next", _start_level.bind(index+1), true)
		_modal_button("重试这一关", "retry", _retry_current)
		_modal_button("选择林地", "result_levels", _show_levels)
	else:
		_modal_button("选择林地", "result_levels", _show_levels, true)
		_modal_button("重试这一关", "retry", _retry_current)
	_modal_button("复制战绩 · 发给朋友", "share", _copy_result)
	audio.play_cue("win" if won else "lose")
	_focus("challenge_next" if game_mode == "challenge" and won else ("next" if won and index < S.LEVELS.size()-1 else "result_levels"))

func _result_text() -> String:
	var result: Dictionary = sim.stats(state)
	var context := "巡护 #%d · 守住 %d 片 · %d 分" % [challenge_root,challenge_completed,challenge_score] if game_mode == "challenge" else "第 %d 关 · %s" % [int(state["level"])+1, _current_level()["name"]]
	return "我在《燎原》%s：%s，%d 回合，保留 %d%% 植被。火不听指挥，但会回应每一步布局。#涌现 #燎原" % [context,"★".repeat(int(result["stars"])) if state["status"] == "won" else "防线待改进",result["turn"],roundi(float(result["saved_fraction"])*100)]

func _copy_result() -> void:
	last_share_text = _result_text()
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(last_share_text)
		buttons["share"].text = "已复制，粘贴给朋友"
		_notify("战绩已复制到剪贴板。")
	else:
		_open_modal("share_text", "这次布防，值得留下一句。", "此设备不支持剪贴板，可以选中并复制下面的文本。")
		var text := TextEdit.new()
		text.text = last_share_text
		text.editable = false
		text.custom_minimum_size = Vector2(600,120)
		modal_box.add_child(text)
		_modal_button("返回结算", "back_result", _finish_game)


func _toggle_forecast() -> void:
	forecast_enabled = not forecast_enabled
	_update_game()

func _show_pause() -> void:
	if state.get("status") != "playing":
		return
	_persist()
	_open_modal("pause", "火会等你。", "这里没有倒计时。当前布防已自动保存。")
	_modal_button("继续布防", "resume", _close_modal, true)
	_modal_button("查看规则", "pause_rules", _show_rules)
	_modal_button("重开本关", "restart", _confirm_restart)
	_modal_button("返回主界面（保留本局）", "pause_home", _show_home)
	_focus("resume")

func _confirm_restart() -> void:
	_open_modal("restart", "重新布防？", "本关会恢复同一张地图和风序列，已获得的星级保留。")
	_modal_button("继续当前布防", "cancel", _close_modal)
	_modal_button("确认重开", "confirm_restart", _retry_current, true)

func _show_rules() -> void:
	_open_modal("rules", "规则不多，变化很多。", "目标：保住全部房屋，直到火烧尽。没有倒计时，也没有隐藏的点燃骰子。")
	modal_box.add_child(_wrap("01  热量如何汇聚\n每团火向相邻 8 格供热：通常 +1，沿本次风向 +2。多个火源会叠加；草地、灌木达到 3 热量，树木、房屋达到 4 热量就起火。没有热源时，每轮降温 1。", 15, TEXT))
	modal_box.add_child(_wrap("02  只改地形，不命令火\n铁锹：草地 / 灌木 → 永久防火带。\n斧头：树木 → 草地；再挖一次可形成防火带。\n水壶：清零热量，并阻挡接下来 3 次回合供热。\n每个工具消耗 1 AP，不能在正在燃烧的格子上施工。", 15, TEXT))
	modal_box.add_child(_wrap("03  预判与代价\n橙框准确标出下一轮起火格；每次布防后立即更新。蓝框数字是剩余防火轮数。新火本轮不再传播；草 / 灌 / 树分别传播 2 / 3 / 4 轮后成灰。\n火烧、砍树与挖带都计入植被损失。少做一步，也许能多留一片林。", 15, TEXT))
	modal_box.add_child(_wrap("手机操作：点「查看」后观察格子，不消耗 AP；选工具切回施工。「等待余火」只在模拟确认无需继续布防时启用。巡护挑战按编号生成新林地，相同编号可重复。", 14, TEAL))
	modal_box.add_child(_label("1 / 2 / 3 选工具   ·   Space 推进   ·   Z 撤销\nP 预判   ·   Esc 暂停   ·   R 重开   ·   M 声音   ·   F11 全屏", 13, MUTED, true))
	_modal_button("明白了", "close_rules", _close_modal, true)
	_focus("close_rules")

func _show_settings() -> void:
	_open_modal("settings", "按你的节奏。", "辅助显示不会扣分，也不会影响关卡解锁。")
	_modal_button("声音：关" if progress["muted"] else "声音：开", "settings_mute", _toggle_mute)
	_modal_button("减少动态：开" if progress["reduced_motion"] else "减少动态：关", "motion", _toggle_motion)
	_modal_button("高对比预警：开" if progress["high_contrast"] else "高对比预警：关", "contrast", _toggle_contrast)
	_modal_button("切换全屏  F11", "fullscreen", _toggle_fullscreen)
	_modal_button("返回", "close_settings", _close_modal, true)
	_focus("close_settings")

func _toggle_mute() -> void:
	progress["muted"] = not bool(progress["muted"])
	audio.set_muted(bool(progress["muted"]))
	for key: String in ["mute", "settings_mute"]:
		if buttons.has(key) and is_instance_valid(buttons[key]):
			buttons[key].text = "声音：关" if progress["muted"] else "声音：开"
	_persist()

func _toggle_motion() -> void:
	progress["reduced_motion"] = not bool(progress["reduced_motion"])
	reduced_motion = bool(progress["reduced_motion"])
	buttons["motion"].text = "减少动态：开" if reduced_motion else "减少动态：关"
	_persist()

func _toggle_contrast() -> void:
	progress["high_contrast"] = not bool(progress["high_contrast"])
	buttons["contrast"].text = "高对比预警：开" if progress["high_contrast"] else "高对比预警：关"
	_persist()

func _toggle_fullscreen() -> void:
	var current := DisplayServer.window_get_mode()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if current == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)

func _quit() -> void:
	_persist()
	get_tree().quit()

func _persist() -> void:
	if game_mode == "challenge":
		progress["challenge_session"] = {"root":challenge_root,"sector":challenge_sector,"score":challenge_score,"completed":challenge_completed,"state":sim.serialize_state(state)} if state.get("status") == "playing" else {}
	else:
		progress["session"] = sim.serialize_state(state) if state.get("status") == "playing" else {}
	progress["active_mode"] = game_mode
	if not store.save_progress(progress):
		_notify(store.last_error, true)

func _open_modal(kind: String, title: String, subtitle: String) -> void:
	_clear(modal_layer)
	modal_kind = kind
	modal_layer.visible = true
	var dim := ColorRect.new()
	dim.color = Color(0.025,0.065,0.07,.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal_layer.add_child(center)
	var scroll := ScrollContainer.new()
	modal_scroll = scroll
	scroll.custom_minimum_size = Vector2(690, 0)
	scroll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	center.add_child(scroll)
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(690, 0)
	box.add_theme_stylebox_override("panel", _style(PANEL, BORDER, 16))
	scroll.add_child(box)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	box.add_child(margin)
	modal_box = VBoxContainer.new()
	modal_box.custom_minimum_size.x = 630
	modal_box.add_theme_constant_override("separation", 14)
	margin.add_child(modal_box)
	modal_box.add_child(_label(title, 30, TEXT, true))
	var sub := _wrap(subtitle, 15, MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal_box.add_child(sub)
	_separator(modal_box)
	_scroll_modal_size.call_deferred(scroll, box)
	if is_instance_valid(board):
		board.interactive = false

func _scroll_modal_size(scroll: ScrollContainer, box: PanelContainer) -> void:
	if not is_instance_valid(scroll) or not is_instance_valid(box):
		return
	modal_natural_height = box.get_combined_minimum_size().y
	scroll.custom_minimum_size.y = minf(modal_natural_height, get_viewport_rect().size.y - 32)

func _close_modal() -> void:
	if not is_instance_valid(modal_layer):
		return
	if not modal_kind.is_empty():
		modal_scroll.scroll_vertical = 0
	modal_kind = ""
	modal_layer.visible = false
	_clear(modal_layer)
	modal_scroll = null
	if _compact_window() != mobile_layout:
		_schedule_layout()
	if page == "game" and not state.is_empty():
		_update_game()

func _modal_button(text: String, id: String, action: Callable, primary: bool = false) -> Button:
	return _button(modal_box, text, id, action, primary, 0, 44)

func _button(parent: Node, text: String, id: String, action: Callable, primary: bool = false, min_width: float = 0, min_height: float = 48) -> Button:
	var button := Button.new()
	button.name = "Button_" + id
	button.text = text
	button.custom_minimum_size = Vector2(min_width, min_height)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 15 if text.contains("\n") else 16)
	if primary:
		button.add_theme_stylebox_override("normal", _style(Color("#b47c49"), Color("#dcab72"), 9))
		button.add_theme_stylebox_override("hover", _style(Color("#c8975d"), Color("#ffe3a8"), 9))
		button.add_theme_color_override("font_color", Color("#fff7df"))
	button.pressed.connect(func() -> void:
		if not button.disabled:
			audio.play_cue("select")
			action.call()
	)
	parent.add_child(button)
	buttons[id] = button
	return button

func _label(text: String, font_size: int = 16, color: Color = TEXT, centered: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_constant_override("line_spacing", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _wrap(text: String, font_size: int = 16, color: Color = TEXT) -> Label:
	var l := _label(text, font_size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

func _game_sidebar(parent: Node) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(302, 0)
	panel.add_theme_stylebox_override("panel", _style(PANEL, BORDER))
	parent.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 250
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return box

func _panel_vbox(parent: Node) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(PANEL, BORDER))
	parent.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	return box

func _metric(parent: Node, caption: String, value: String, id: String, font_size: int) -> void:
	var box := _panel_vbox(parent)
	box.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 3)
	box.add_child(_label(caption, 12, MUTED))
	var l := _label(value, font_size, GOLD if id == "level_name" else TEXT)
	box.add_child(l)
	labels[id] = l

func _spacer(parent: Node, vertical: bool = false) -> void:
	var c := Control.new()
	if vertical:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)

func _separator(parent: Node) -> void:
	var line := ColorRect.new()
	line.color = BORDER
	line.custom_minimum_size.y = 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)

func _notify(text: String, warning: bool = false) -> void:
	message = text
	message_time = 6.0 if warning else 4.0
	if is_instance_valid(status_label):
		status_label.text = text
		status_label.modulate = RED if warning else Color.WHITE

func _focus(id: String) -> void:
	if buttons.has(id):
		buttons[id].call_deferred("grab_focus")

func _wind_text(direction: int) -> String:
	return ["向北", "向东北", "向东", "向东南", "向南", "向西南", "向西", "向西北"][posmod(direction,8)]
