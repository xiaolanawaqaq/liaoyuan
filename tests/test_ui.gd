extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const S := preload("res://scripts/sim.gd")
const Store := preload("res://scripts/save_store.gd")
var game
var passed := 0
var failed := 0
var evidence: Array[Dictionary] = []
var screenshot_dir := ""
var test_save := ""

func _init() -> void:
	call_deferred("_run")

func check(condition: bool, name_text: String) -> void:
	evidence.append({"name": name_text, "passed": condition})
	if condition:
		passed += 1
		print("PASS ", name_text)
	else:
		failed += 1
		push_error("FAIL " + name_text)

func _frames(count: int = 3) -> void:
	for _i: int in range(count):
		await process_frame

func _press(id: String) -> void:
	check(game.buttons.has(id) and is_instance_valid(game.buttons[id]), "button exists: " + id)
	if not game.buttons.has(id) or not is_instance_valid(game.buttons[id]):
		return
	var b: Button = game.buttons[id]
	check(b.is_visible_in_tree() and not b.disabled, "button enabled: " + id)
	var p: Vector2 = b.get_global_rect().get_center()
	await _click(p)

func _click(p: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = p
	motion.global_position = p
	Input.parse_input_event(motion)
	await _frames(1)
	var down := InputEventMouseButton.new()
	down.position = p
	down.global_position = p
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	Input.parse_input_event(down)
	await _frames(1)
	var up := InputEventMouseButton.new()
	up.position = p
	up.global_position = p
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(3)

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(1)
	event = InputEventKey.new()
	event.keycode = code
	Input.parse_input_event(event)
	await _frames(3)

func _cell(c: int, r: int) -> void:
	var p: Vector2 = game.board.global_position + game.board.cell_center(Vector2i(c,r))
	await _click(p)

func _shot(name_text: String) -> void:
	if screenshot_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await _frames(5)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image != null and not image.is_empty(), "viewport rendered: " + name_text)
	if image != null and not image.is_empty():
		var error := image.save_png(screenshot_dir.path_join(name_text + ".png"))
		check(error == OK, "screenshot saved: " + name_text)

func _bounds(node: Node, bounds: Rect2) -> void:
	if node is Button and node.is_visible_in_tree():
		var rect: Rect2 = node.get_global_rect()
		check(bounds.grow(1).encloses(rect), "visible button within viewport: " + node.name)
	for child: Node in node.get_children():
		_bounds(child, bounds)

func _spawn() -> void:
	game = MainScene.instantiate()
	root.add_child(game)
	await _frames(6)

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			screenshot_dir = arg.trim_prefix("--shots=")
		if arg.begins_with("--save-path="):
			test_save = arg.trim_prefix("--save-path=")
	if test_save.is_empty():
		push_error("UI tests require --save-path=<unique test path>, never use player saves")
		quit(2)
		return
	if not screenshot_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(screenshot_dir)
	root.size = Vector2i(1200,820)
	await _spawn()
	check(game.page == "home", "fresh launch opens home")
	check(game.progress["unlocked"] == 0, "fresh save locks later levels")
	_bounds(game, Rect2(Vector2.ZERO,Vector2(1200,820)))
	await _shot("01-home")
	await _press("rules")
	check(game.modal_kind == "rules", "rules button opens readable modal")
	_bounds(game, Rect2(Vector2.ZERO,Vector2(1200,820)))
	await _shot("02-rules")
	await _press("close_rules")
	check(game.modal_kind.is_empty(), "rules closes")
	await _press("levels")
	check(game.page == "levels", "level selection opens")
	check(game.buttons["level_1"].disabled, "second level initially locked")
	_bounds(game, Rect2(Vector2.ZERO,Vector2(1200,820)))
	await _shot("03-levels-locked")
	await _press("level_0")
	check(game.page == "game" and game.state["turn"] == 1, "level button starts playable map")
	check(game.selected_tool == "shovel", "first lesson has shovel selected")
	_bounds(game, Rect2(Vector2.ZERO,Vector2(1200,820)))
	await _shot("04-first-turn")
	var ap_before: int = int(game.state["ap"])
	await _cell(0,0)
	check(int(game.state["ap"]) == ap_before, "invalid map click consumes no action")
	await _cell(5,3)
	check(game.state["cells"][3*S.COLS+5]["tile"] == S.FIREBREAK and int(game.state["ap"]) == 2, "native map click digs and spends AP")
	await _press("undo")
	check(game.state["cells"][3*S.COLS+5]["tile"] == S.GRASS and int(game.state["ap"]) == 3, "undo button restores grid and AP")
	await _key(KEY_2)
	check(game.selected_tool == "axe", "keyboard 2 selects axe")
	await _key(KEY_1)
	check(game.selected_tool == "shovel", "keyboard 1 selects shovel")
	await _cell(5,3)
	var serial_before: Dictionary = game.sim.serialize_state(game.state)
	await _key(KEY_ESCAPE)
	check(game.modal_kind == "pause", "Escape pauses without abandoning")
	await _shot("05-pause")
	await _press("resume")
	check(game.sim.serialize_state(game.state) == serial_before, "pause/resume preserves entire state")
	await _press("pause")
	await _press("pause_home")
	check(game.page == "home" and game.buttons.has("continue"), "home offers resume")
	await _press("continue")
	check(game.sim.serialize_state(game.state) == serial_before, "home resume preserves entire state")
	await _press("pause")
	await _press("restart")
	check(game.modal_kind == "restart", "restart has confirmation")
	await _press("cancel")
	check(game.sim.serialize_state(game.state) == serial_before, "cancel restart preserves state")
	await _press("settings")
	await _press("settings_mute")
	await _press("motion")
	await _press("contrast")
	check(game.progress["muted"] and game.progress["reduced_motion"] and game.progress["high_contrast"], "accessibility settings toggle")
	await _shot("06-settings")
	await _press("close_settings")
	var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(game.store.path))
	check(disk is Dictionary and game.sim.deserialize_state(disk.get("session")).size() > 0, "midturn state saved with settings")
	root.remove_child(game)
	game.queue_free()
	await _frames(3)
	await _spawn()
	check(game.page == "home" and game.buttons.has("continue"), "new scene process entry restores session offer")
	await _press("continue")
	check(game.sim.serialize_state(game.state) == serial_before, "reloaded save restores same midturn state")
	check(game.progress["muted"] and game.progress["reduced_motion"] and game.progress["high_contrast"], "settings survive reload")
	await _press("settings")
	await _press("motion")
	await _press("contrast")
	await _press("close_settings")
	await _key(KEY_R)
	await _press("confirm_restart")
	check(game.state["turn"] == 1 and int(game.state["ap"]) == 3, "confirmed restart resets same map")
	var solutions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/solutions.json"))
	for entry: Dictionary in solutions["levels"]:
		var level: int = int(entry["index"])
		check(int(game.state["level"]) == level, "campaign starts expected level %d" % (level+1))
		for turn_actions: Array in entry["turns"]:
			for action: Dictionary in turn_actions:
				await _press("tool_" + str(action["tool"]))
				var before_ap: int = int(game.state["ap"])
				await _cell(int(action["c"]), int(action["r"]))
				check(int(game.state["ap"]) == before_ap - 1, "L%d legitimate action at %s,%s" % [level+1,action["c"],action["r"]])
			if level == 0 and int(game.state["turn"]) == 3:
				await _shot("07-first-defence")
			if level == 3 and int(game.state["turn"]) == 3:
				await _shot("08-two-fronts")
			if level == 4 and int(game.state["turn"]) == 4:
				await _shot("09-final-forest")
			await _press("end")
			await create_timer(.36).timeout
		check(game.state["status"] == "won", "L%d won through visible controls" % (level+1))
		check(game.modal_kind == "result", "L%d result modal is active" % (level+1))
		check(int(game.progress["stars"].get(str(level),0)) == 3, "L%d earns and stores three stars" % (level+1))
		check(int(game.progress["unlocked"]) == mini(level+1,4), "L%d advances campaign unlock" % (level+1))
		if level == 0:
			await _shot("10-win")
		if level < 4:
			await _press("next")
	await _shot("11-campaign-complete")
	await _press("result_levels")
	check(game.page == "levels", "completion returns to real level selection")
	for i: int in range(5):
		check(not game.buttons["level_%d"%i].disabled,"completed level remains playable %d"%(i+1))
	await _shot("12-levels-complete")
	await _press("level_0")
	for _i: int in range(20):
		if game.state["status"] != "playing":
			break
		await _press("end")
		await create_timer(.36).timeout
	check(game.state["status"] == "lost", "inaction reaches genuine loss")
	check(game.modal_kind == "result", "loss has functional result modal")
	await _shot("13-loss")
	await _press("retry")
	check(game.state["status"] == "playing" and int(game.state["turn"]) == 1, "retry after loss starts same level")
	check(int(game.progress["stars"]["0"]) == 3, "loss never reduces earned stars")
	await _cell(5,3)
	await _key(KEY_Z)
	check(int(game.state["ap"]) == 3,"keyboard undo works")
	await _key(KEY_P)
	check(not game.forecast_enabled,"keyboard forecast toggle works")
	await _key(KEY_P)
	var turn_before: int = int(game.state["turn"])
	await _key(KEY_SPACE)
	await create_timer(.36).timeout
	check(int(game.state["turn"]) == turn_before+1,"Space advances exactly one turn")
	await _key(KEY_ESCAPE)
	await _press("pause_home")
	_bounds(game,Rect2(Vector2.ZERO,Vector2(1200,820)))
	if not screenshot_dir.is_empty():
		var f := FileAccess.open(screenshot_dir.path_join("ui-evidence.json"),FileAccess.WRITE)
		f.store_string(JSON.stringify({"passed":passed,"failed":failed,"checks":evidence},"\t"))
	print("UI RESULTS: %d passed, %d failed" % [passed,failed])
	quit(1 if failed else 0)
