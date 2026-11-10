extends "res://tests/test_ui.gd"

const C := preload("res://scripts/challenge_sim.gd")

func _scroll_to(control: Control) -> void:
	var ancestor: Node = control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(control)
			await _frames(4)
		ancestor = ancestor.get_parent()

func _press(id: String) -> void:
	if game.buttons.has(id) and is_instance_valid(game.buttons[id]):
		await _scroll_to(game.buttons[id])
	await super._press(id)

func _click(position: Vector2) -> void:
	var window_position: Vector2 = root.get_final_transform() * position
	await super._click(window_position)

func _tap_cell(c: int, r: int) -> void:
	var position: Vector2 = root.get_final_transform() * (game.board.global_position + game.board.cell_center(Vector2i(c,r)))
	var touch := InputEventScreenTouch.new()
	touch.position = position
	touch.index = 0
	touch.pressed = true
	Input.parse_input_event(touch)
	await _frames(2)
	touch = InputEventScreenTouch.new()
	touch.position = position
	touch.index = 0
	touch.pressed = false
	Input.parse_input_event(touch)
	await _frames(3)

func _type(text: String) -> void:
	for character: String in text:
		var event := InputEventKey.new()
		event.unicode = character.unicode_at(0)
		event.pressed = true
		Input.parse_input_event(event)
		await _frames(1)
		event = InputEventKey.new()
		event.unicode = character.unicode_at(0)
		Input.parse_input_event(event)
	await _frames(3)

func _bounded_buttons() -> void:
	var bounds: Rect2 = game.get_viewport_rect()
	for id: String in game.buttons:
		var button: Button = game.buttons[id]
		if not is_instance_valid(button) or not button.is_visible_in_tree():
			continue
		await _scroll_to(button)
		check(bounds.grow(1).encloses(button.get_global_rect()), "usable button in viewport: " + id)
		var ancestor: Node = button.get_parent()
		while ancestor != null:
			if ancestor is ScrollContainer:
				check(ancestor.get_global_rect().grow(1).encloses(button.get_global_rect()), "scroll exposes button: " + id)
			ancestor = ancestor.get_parent()

func _wait_for_result(seconds: float = 24.0) -> void:
	var elapsed := 0.0
	while game.state.get("status") == "playing" and elapsed < seconds:
		await create_timer(.2).timeout
		elapsed += .2
	check(game.state.get("status") != "playing", "auto wait reaches a genuine result within limit")

func _defend_challenge() -> void:
	var plan: Array = C.new().witness(int(game.state["seed"]))
	for actions: Array in plan:
		for action: Dictionary in actions:
			await _press("tool_" + str(action["tool"]))
			var before: int = int(game.state["ap"])
			await _cell(int(action["c"]), int(action["r"]))
			check(int(game.state["ap"]) == before - 1, "challenge action through actual board input")
		await _press("end")
		await create_timer(.4).timeout
	check(not game.buttons["wait"].disabled, "constructed challenge defense unlocks safe wait")
	await _press("wait")
	await _wait_for_result()
	check(game.state["status"] == "won", "challenge victory uses legal actions and real fire exhaustion")

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			screenshot_dir = arg.trim_prefix("--shots=")
		if arg.begins_with("--save-path="):
			test_save = arg.trim_prefix("--save-path=")
	if test_save.is_empty():
		push_error("V030 UI tests require isolated --save-path")
		quit(2)
		return
	if not screenshot_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(screenshot_dir)
	root.size = Vector2i(1200,820)
	await _spawn()
	await _press("start")
	check(game.game_mode == "campaign", "start enters original campaign")
	check(game.board.tutorial_cells.size() == 3, "tutorial highlights actual three-cell defense")
	check(game.buttons["wait"].disabled, "unsafe fresh fire cannot be fast-forwarded")
	var before: Dictionary = game.sim.serialize_state(game.state)
	await _press("inspect")
	check(game.inspect_mode and game.board.inspect_only, "inspect button switches to safe viewing")
	await _cell(5,3)
	check(game.sim.serialize_state(game.state) == before, "inspect click changes no simulation/AP/scoring state")
	check(game.labels["detail_name"].text.begins_with("F4"), "click without hover exposes chosen cell details")
	check(game.labels["detail"].text.contains("热量") and game.labels["detail"].text.contains("不消耗"), "inspect shows heat and no-cost promise")
	await _tap_cell(5,4)
	check(game.sim.serialize_state(game.state) == before and game.labels["detail_name"].text.begins_with("F5"), "actual screen touch inspects without spending or needing hover")
	await _shot("01-inspect")
	await _press("tool_shovel")
	check(not game.inspect_mode, "selecting a tool explicitly resumes construction")
	await _tap_cell(5,3)
	check(int(game.state["ap"]) == 2, "screen-touch construction consumes exactly one AP without emulated double click")
	await _press("undo")
	check(game.sim.serialize_state(game.state) == before, "undo also restores inspector construction change")
	await _key(KEY_I)
	check(game.inspect_mode, "I toggles inspection")
	await _key(KEY_I)
	check(not game.inspect_mode, "I toggles back to construction")
	await _cell(5,3)
	await _cell(5,4)
	await _cell(5,5)
	check(game.board.tutorial_cells.is_empty(), "tutorial markers disappear only after real defense")
	check(not game.buttons["wait"].disabled, "safe wait enabled while fire still exists")
	check(game.sim.burning_count(game.state) > 0, "safe wait is not a dead post-victory branch")
	await _press("wait")
	check(game.auto_waiting and game.buttons["tool_shovel"].disabled, "auto wait locks construction")
	await _key(KEY_ESCAPE)
	check(not game.auto_waiting and game.state["turn"] == 1, "Escape cancels wait before first advance")
	await _press("wait")
	await _wait_for_result()
	check(game.state["status"] == "won" and game.modal_kind == "result", "safe wait completes real campaign victory")
	check(game.sim.stats(game.state)["turn"] == 6, "auto wait preserves exact original solution turn count")
	await _press("share")
	check(game.last_share_text.contains("第 1 关") and game.last_share_text.contains("86%") and game.last_share_text.contains("★★★"), "share text reflects real rounded campaign result")
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		check(DisplayServer.clipboard_get() == game.last_share_text, "clipboard actually contains share text")
	await _shot("02-share-result")
	await _press("result_levels")
	await _press("home")
	await _press("challenge")
	check(game.modal_kind == "challenge_setup", "challenge has visible setup entry")
	var input: LineEdit = game.find_child("ChallengeSeed", true, false)
	await _click(input.get_global_rect().get_center())
	await _type("12345")
	check(input.text == "12345", "challenge seed is entered through real keyboard events")
	await _press("challenge_start")
	check(game.game_mode == "challenge" and game.challenge_root == 12345 and game.challenge_sector == 1, "numbered challenge begins at sector one")
	var initial: Dictionary = game.sim.serialize_state(game.state)
	var campaign_stars: Dictionary = game.progress["stars"].duplicate(true)
	await _shot("03-challenge-seed")
	await _defend_challenge()
	var score: int = game.challenge_score
	check(score > 0 and game.challenge_completed == 1, "real challenge result records score and completed sector")
	check(game.progress["stars"] == campaign_stars, "challenge does not grant campaign stars")
	await _press("share")
	check(game.last_share_text.contains("#12345") and game.last_share_text.contains(str(score)), "challenge share includes reproducible root seed and score")
	await _shot("04-challenge-win")
	await _press("challenge_next")
	check(game.challenge_sector == 2 and game.challenge_score == score and game.challenge_completed == 1, "next sector carries earned score only once")
	check(game.state["seed"] != initial["seed"], "next sector genuinely changes generated terrain seed")
	var saved_state: Dictionary = game.sim.serialize_state(game.state)
	await _press("pause")
	await _press("pause_home")
	var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(game.store.path))
	check(disk["active_mode"] == "challenge" and int(disk["challenge_session"]["sector"]) == 2, "separate challenge envelope written to real save file")
	root.remove_child(game)
	game.queue_free()
	await _frames(3)
	await _spawn()
	await _press("continue")
	check(game.game_mode == "challenge" and game.challenge_sector == 2 and game.challenge_score == score, "relaunch restores challenge mode/sector/score")
	check(game.sim.serialize_state(game.state) == saved_state, "challenge relaunch restores exact planning grid")
	await _defend_challenge()
	check(game.challenge_completed == 2 and game.challenge_score > score, "second legal sector accumulates score")
	await _press("challenge_next")
	var preserved_score: int = game.challenge_score
	for _i: int in range(20):
		if game.state["status"] != "playing":
			break
		await _press("end")
		await create_timer(.4).timeout
	check(game.state["status"] == "lost", "unprotected procedural sector reaches real defeat")
	check(game.challenge_score == preserved_score and game.progress["challenge_best"] >= preserved_score, "loss retains earned local high score")
	await _press("retry")
	check(game.challenge_sector == 1 and game.challenge_score == 0 and game.sim.serialize_state(game.state) == initial, "retry restarts same root seed without carrying score")
	await _press("pause")
	await _press("pause_home")
	for dimensions: Vector2i in [Vector2i(1200,600), Vector2i(1066,600), Vector2i(1200,540)]:
		root.size = dimensions
		await _frames(12)
		check(game.mobile_layout, "compact layout chosen at " + str(dimensions))
		await _bounded_buttons()
		await _shot("05-mobile-home-%d-%d" % [dimensions.x,dimensions.y])
		await _press("continue")
		await _bounded_buttons()
		await _shot("06-mobile-game-%d-%d" % [dimensions.x,dimensions.y])
		await _press("header_rules")
		await _bounded_buttons()
		await _press("close_rules")
		await _press("pause")
		await _press("pause_home")
	if not screenshot_dir.is_empty():
		var f := FileAccess.open(screenshot_dir.path_join("ui-v030-evidence.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify({"passed":passed,"failed":failed,"checks":evidence}, "\t"))
	print("V030 UI RESULTS: %d passed, %d failed" % [passed,failed])
	root.remove_child(game)
	game.queue_free()
	await _frames(3)
	quit(1 if failed else 0)
