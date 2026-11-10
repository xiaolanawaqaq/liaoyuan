extends SceneTree

# Read-only audit harness. Production resources are preloaded by instance type,
# not by their editor/global-class cache. All writable paths require QA isolation.
const StoreScript := preload("res://scripts/save_store.gd")
const SimScript := preload("res://scripts/sim.gd")
const SOLUTIONS_PATH := "res://tests/solutions.json"
var sim: SimScript = SimScript.new()
var evidence_dir := ""
var case_dir := ""
var mode := "core"
var passed := 0
var failed := 0
var checks: Array[Dictionary] = []
var started := Time.get_ticks_msec()

func _init() -> void:
	call_deferred("_run")

func check(condition: bool, label: String, detail: String = "") -> void:
	checks.append({"name": label, "passed": condition, "detail": detail})
	if condition:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		print("FAIL ", label, " | ", detail)

func _store(path_value: String) -> StoreScript:
	assert(path_value.begins_with(evidence_dir + "/"), "Never access player saves")
	var store: StoreScript = StoreScript.new()
	store.path = path_value
	return store

func _path(name_text: String) -> String:
	return case_dir.path_join(name_text)

func _write(path_value: String, text: String) -> void:
	assert(path_value.begins_with(evidence_dir + "/"))
	var file := FileAccess.open(path_value, FileAccess.WRITE)
	check(file != null, "fixture write " + path_value.get_file())
	if file != null:
		file.store_string(text)
		file.close()

func _backups(path_value: String) -> Array[String]:
	var found: Array[String] = []
	for name_text: String in DirAccess.get_files_at(path_value.get_base_dir()):
		if name_text.begins_with(path_value.get_file() + ".recovered-"):
			found.append(path_value.get_base_dir().path_join(name_text))
	return found

func _solutions() -> Array:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOLUTIONS_PATH))
	if not raw is Dictionary or not raw.get("levels") is Array:
		check(false, "read five solution fixtures")
		return []
	return raw["levels"]

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="):
			evidence_dir = arg.trim_prefix("--evidence=")
		elif arg.begins_with("--mode="):
			mode = arg.trim_prefix("--mode=")
	if not evidence_dir.is_absolute_path() or evidence_dir.contains("..") or mode.contains("/"):
		print("ERROR: require a unique absolute --evidence=<dir> outside the project, e.g. /tmp/liaoyuan-qa/persistence-<id>")
		quit(2)
		return
	case_dir = evidence_dir.path_join("cases").path_join(mode)
	if DirAccess.make_dir_recursive_absolute(case_dir) != OK:
		quit(2)
		return
	print("PERSISTENCE MODE ", mode, " | ", Engine.get_version_info()["string"])
	match mode:
		"core":
			_fresh()
			var campaign := _campaign()
			_malformed_progress()
			_malformed_sessions(campaign)
		"reload":
			_reload_process()
		"denied":
			_denials()
		_:
			_version_probe()
	var summary := {"mode": mode, "passed": passed, "failed": failed, "elapsed_ms": Time.get_ticks_msec() - started, "checks": checks}
	var output := FileAccess.open(evidence_dir.path_join(mode + "-results.json"), FileAccess.WRITE)
	if output == null:
		print("ERROR: cannot write audit results")
		quit(2)
		return
	output.store_string(JSON.stringify(summary, "\t"))
	output.close()
	print("RESULT ", mode, ": ", passed, " passed, ", failed, " failed")
	quit(1 if failed > 0 else 0)

func _fresh() -> void:
	var store := _store(_path("fresh.json"))
	check(not FileAccess.file_exists(store.path), "fresh path is unique and absent")
	var initial := store.load_progress()
	check(initial == store.defaults() and not store.recovered and store.last_error.is_empty(), "missing save returns clean defaults")
	check(not FileAccess.file_exists(store.path), "load alone does not create a save")
	var independent := store.defaults()
	independent["stars"]["0"] = 3
	independent["session"]["test"] = true
	check(store.defaults()["stars"].is_empty() and initial["session"].is_empty(), "defaults have independent nested dictionaries")
	for key: String in ["muted", "reduced_motion", "high_contrast", "tutorial_done"]:
		initial[key] = true
	check(store.save_progress(initial), "fresh preferences actually written", store.last_error)
	check(_store(store.path).load_progress() == initial, "new store reloads preferences and defaults")
	initial["muted"] = false
	check(store.save_progress(initial) and _store(store.path).load_progress() == initial, "second save atomically replaces prior JSON")
	check(not FileAccess.file_exists(store.path + ".tmp"), "successful save leaves no temporary file")

func _session_file(progress: Dictionary, state: Dictionary, path_value: String, label: String) -> Dictionary:
	var before := state.duplicate(true)
	var payload := progress.duplicate(true)
	payload["session"] = sim.serialize_state(state)
	check(not payload["session"].is_empty() and state == before, label + " serializes without mutation")
	var store := _store(path_value)
	check(store.save_progress(payload), label + " writes real file", store.last_error)
	var loaded := _store(path_value).load_progress()
	var restored := sim.deserialize_state(loaded.get("session"))
	check(restored == state and not restored.is_empty(), label + " reloads every state field exactly")
	check(loaded["stars"] == progress["stars"] and loaded["unlocked"] == progress["unlocked"], label + " preserves earned progress")
	return restored if not restored.is_empty() else state

func _campaign() -> Dictionary:
	var entries := _solutions()
	check(entries.size() == 5, "exactly five campaign solutions")
	var store := _store(_path("campaign.json"))
	var progress := store.defaults()
	for key: String in ["muted", "reduced_motion", "high_contrast"]:
		progress[key] = true
	for entry: Dictionary in entries:
		var level := int(entry["index"])
		var label := "L%d" % (level + 1)
		var session_path := _path("session-l%d.json" % level)
		var state := sim.new_game(level, int(entry["seed"]))
		state = _session_file(progress, state, session_path, label + " initial")
		for actions: Array in entry["turns"]:
			for action: Dictionary in actions:
				var applied := sim.apply_tool(state, int(action["c"]), int(action["r"]), str(action["tool"]))
				check(bool(applied["ok"]), label + " solution action is legal", str(action))
				state = _session_file(progress, state, session_path, label + " T%d mid-planning" % int(state["turn"]))
			sim.end_turn(state)
			if state["status"] == "playing":
				state = _session_file(progress, state, session_path, label + " T%d after resolution" % int(state["turn"]))
		var result := sim.stats(state)
		var expected: Dictionary = entry["expected"]
		check(state["status"] == "won" and result["stars"] == 3 and result["turn"] == int(expected["turns"]) and result["saved_value"] == int(expected["saved_value"]) and result["actions_used"] == int(expected["actions"]), label + " genuine solution victory matches fixture", JSON.stringify(result))
		check(sim.deserialize_state(JSON.parse_string(JSON.stringify(sim.serialize_state(state)))) == state, label + " terminal state is serializable")
		store.record_win(progress, level, result)
		check(progress["stars"][str(level)] == 3 and progress["unlocked"] == mini(level + 1, 4) and progress["tutorial_done"] and progress["session"].is_empty(), label + " records stars, unlock and cleared session")
		check(store.save_progress(progress), label + " victory saved to disk", store.last_error)
		progress = _store(store.path).load_progress()
		check(progress["stars"].size() == level + 1 and progress["stars"][str(level)] == 3 and progress["best"][str(level)]["turns"] == result["turn"] and absf(float(progress["best"][str(level)]["saved"]) - float(result["saved_fraction"])) < 0.000001, label + " victory survives new store reload")
		print("VICTORY ", label, " stars=", result["stars"], " turns=", result["turn"], " saved=", result["saved_value"], "/", result["init_value"])
	var best_before: Dictionary = progress["best"].duplicate(true)
	for level in range(5):
		# Direct record_win API regression, not a claim of an additional sim win.
		store.record_win(progress, level, {"stars": 1, "saved_fraction": 0.05, "turn": 99})
	check(progress["stars"] == {"0": 3, "1": 3, "2": 3, "3": 3, "4": 3} and progress["best"] == best_before and progress["unlocked"] == 4, "lower-result submissions cannot reduce maximum stars, bests or unlocks")
	check(store.save_progress(progress), "immutable maximum stars saved again", store.last_error)
	var reloaded := _store(store.path).load_progress()
	check(reloaded["stars"] == progress["stars"] and reloaded["best"] == best_before, "maximum stars and bests remain immutable across disk reload")
	if entries.size() == 5:
		var mid := _midturn_state(entries[4])
		_session_file(progress, mid, _path("pause-midturn.json"), "pause/exit with wet cells, heat and spent AP")
		var original := mid.duplicate(true)
		var encoded := sim.serialize_state(mid)
		encoded["cells"][0]["heat"] = 99
		check(mid == original, "serialize_state deeply isolates nested cells")
		var raw: Dictionary = JSON.parse_string(JSON.stringify(mid))
		var decoded := sim.deserialize_state(raw)
		decoded["cells"][0]["heat"] = 99
		check(raw["cells"][0]["heat"] == original["cells"][0]["heat"], "deserialize_state does not alias caller JSON")
	return progress

func _midturn_state(entry: Dictionary) -> Dictionary:
	var state := sim.new_game(int(entry["index"]), int(entry["seed"]))
	for turn in range(3):
		for action: Dictionary in entry["turns"][turn]:
			sim.apply_tool(state, int(action["c"]), int(action["r"]), str(action["tool"]))
		sim.end_turn(state)
	var action: Dictionary = entry["turns"][3][0]
	sim.apply_tool(state, int(action["c"]), int(action["r"]), str(action["tool"]))
	return state

func _bad_json(name_text: String, text: String) -> void:
	var store := _store(_path(name_text + ".json"))
	_write(store.path, text)
	var loaded := store.load_progress()
	check(loaded == store.defaults() and store.recovered and not store.last_error.is_empty(), name_text + " recovers to defaults with a readable warning")
	check(FileAccess.get_file_as_string(store.path) == text, name_text + " load preserves corrupt source bytes")
	check(store.save_progress(loaded), name_text + " can save recovered progress", store.last_error)
	var backups := _backups(store.path)
	check(backups.size() == 1 and FileAccess.get_file_as_string(backups[0]) == text, name_text + " retains exact original backup")
	check(_store(store.path).load_progress() == store.defaults(), name_text + " replacement JSON is readable")

func _malformed_progress() -> void:
	var bad_texts := ["", "{", "not json", "[]", "null", "true", "42", "\"save\"", "{}", "{\"version\":1}"]
	for index in bad_texts.size():
		_bad_json("corrupt-%d" % index, bad_texts[index])
	var complete := FileAccess.get_file_as_string(_path("pause-midturn.json"))
	for length_value: int in [1, int(complete.length() / 2.0), complete.length() - 1]:
		_bad_json("truncated-%d" % length_value, complete.substr(0, length_value))
	var index := 0
	for bad: Variant in [null, true, "4", [], {}]:
		var store := _store(_path("wrong-types-%d.json" % index))
		var raw := {"version": 2, "unlocked": bad, "stars": {"0": bad}, "best": {"0": {"saved": bad, "turns": 4}, "1": {"saved": 0.9, "turns": bad}}, "muted": 1, "reduced_motion": "yes", "high_contrast": [], "tutorial_done": {}, "session": bad}
		_write(store.path, JSON.stringify(raw))
		check(store.load_progress() == store.defaults(), "wrong progress field types safely ignored %d" % index)
		index += 1
	var store := _store(_path("fractional-unlocked.json"))
	_write(store.path, JSON.stringify({"version": 2, "unlocked": 2.75}))
	var loaded := store.load_progress()
	check(loaded["unlocked"] == 0, "nonintegral unlocked is rejected, not silently truncated", JSON.stringify(loaded))
	store = _store(_path("fractional-stars.json"))
	_write(store.path, JSON.stringify({"version": 2, "stars": {"0": 2.75, "1": 1.25, "4": 0.5}}))
	loaded = store.load_progress()
	check(loaded["stars"].is_empty() and loaded["unlocked"] == 0, "nonintegral stars are rejected without granting unlocks", JSON.stringify(loaded))
	store = _store(_path("valid-siblings.json"))
	_write(store.path, JSON.stringify({"version": 2.0, "unlocked": -4, "stars": {"1": 2.0, "3": "3", "9": 3}, "best": {"1": {"saved": 0.5, "turns": 5}, "4": {"saved": "bad", "turns": []}}, "muted": true}))
	loaded = store.load_progress()
	check(loaded["unlocked"] == 2 and loaded["stars"] == {"1": 2} and loaded["best"] == {"1": {"saved": 0.5, "turns": 5}} and loaded["muted"], "valid sibling fields survive partial corruption and integral JSON floats")
	store = _store(_path("integer-bounds.json"))
	_write(store.path, JSON.stringify({"version": 2, "unlocked": 99, "stars": {"0": -2, "4": 99}}))
	loaded = store.load_progress()
	check(loaded["unlocked"] == 4 and loaded["stars"] == {"0": 0, "4": 3}, "out-of-range integer values clamp to documented campaign bounds")
	for bad_version: Variant in ["2", 2.75]:
		store = _store(_path("version-coercion-%s.json" % str(bad_version)))
		_write(store.path, JSON.stringify({"version": bad_version, "unlocked": 4, "stars": {"4": 3}}))
		loaded = store.load_progress()
		check(loaded == store.defaults() and store.recovered and not store.last_error.is_empty(), "wrong-type/nonintegral schema version rejected: " + str(bad_version), JSON.stringify(loaded))

func _malformed_sessions(campaign: Dictionary) -> void:
	for bad: Variant in [null, true, 7, 1.5, "state", [], {}]:
		check(sim.deserialize_state(bad).is_empty(), "invalid session root rejected " + str(bad))
	var base: Dictionary = JSON.parse_string(JSON.stringify(sim.new_game(0, 103)))
	var edits: Array = [["level", []], ["seed", "103"], ["schema_version", 1.5], ["turn", 2.5], ["ap", {}], ["ap", -1], ["cells", []], ["cells", "bad"], ["forecast", {}], ["danger", {}], ["status", false], ["status", "won"], ["actions_used", 1], ["init_value", -1]]
	for edit: Array in edits:
		var bad := base.duplicate(true)
		bad[edit[0]] = edit[1]
		check(sim.deserialize_state(bad).is_empty(), "malformed session rejected " + str(edit))
	for edit: Array in [["tile", 99], ["burn", []], ["wet", 1.5], ["heat", {}], ["variant", "bad"]]:
		var bad := base.duplicate(true)
		bad["cells"][0][edit[0]] = edit[1]
		check(sim.deserialize_state(bad).is_empty(), "malformed cell rejected " + str(edit))
	var bad := base.duplicate(true)
	bad["cells"][0] = null
	check(sim.deserialize_state(bad).is_empty(), "non-object cell rejected without a crash")
	var progress := campaign.duplicate(true)
	progress["session"] = {"cells": []}
	var store := _store(_path("bad-session-good-progress.json"))
	check(store.save_progress(progress), "malformed session fixture stored alongside earned campaign")
	var loaded := _store(store.path).load_progress()
	check(sim.deserialize_state(loaded["session"]).is_empty() and loaded["stars"] == campaign["stars"] and loaded["unlocked"] == 4, "bad session discarded independently of campaign progress")
	loaded["session"] = {}
	check(store.save_progress(loaded) and _store(store.path).load_progress()["stars"] == campaign["stars"], "saving after invalid session recovery does not erase stars")

func _reload_process() -> void:
	var core_dir := evidence_dir.path_join("cases/core")
	var progress := _store(core_dir.path_join("campaign.json")).load_progress()
	check(progress["unlocked"] == 4 and progress["stars"] == {"0": 3, "1": 3, "2": 3, "3": 3, "4": 3}, "separate Godot process reloads all five three-star victories")
	check(progress["muted"] and progress["reduced_motion"] and progress["high_contrast"] and progress["tutorial_done"] and progress["session"].is_empty(), "separate process retains preferences and completed tutorial")
	var entries := _solutions()
	for entry: Dictionary in entries:
		var level := int(entry["index"])
		var expected: Dictionary = entry["expected"]
		var best: Dictionary = progress["best"].get(str(level), {})
		check(best.get("turns") == int(expected["turns"]) and absf(float(best.get("saved", -1)) - float(expected["saved_value"]) / float(expected["init_value"])) < 0.000001, "separate process retains L%d best result" % (level + 1))
		var original := sim.new_game(level, int(entry["seed"]))
		for turn in entry["turns"].size():
			for action: Dictionary in entry["turns"][turn]:
				sim.apply_tool(original, int(action["c"]), int(action["r"]), str(action["tool"]))
			if turn < entry["turns"].size() - 1:
				sim.end_turn(original)
		var saved := _store(core_dir.path_join("session-l%d.json" % level)).load_progress()
		var resumed := sim.deserialize_state(saved["session"])
		check(resumed == original and not resumed.is_empty(), "separate process restores L%d playing session exactly" % (level + 1))
		if not resumed.is_empty():
			check(sim.end_turn(resumed) == sim.end_turn(original) and resumed == original, "L%d resumed final turn is deterministic" % (level + 1))
	if entries.size() == 5:
		var original := _midturn_state(entries[4])
		var saved := _store(core_dir.path_join("pause-midturn.json")).load_progress()
		var resumed := sim.deserialize_state(saved["session"])
		check(resumed == original and not resumed.is_empty(), "process exit/restart preserves exact midturn AP, water, heat and score")
		if not resumed.is_empty():
			check(sim.end_turn(resumed) == sim.end_turn(original) and resumed == original, "midturn restart continues with identical fire and wind")

func _denials() -> void:
	for name_text: String in ["open", "rename"]:
		var store := _store(_path(name_text + "/progress.json"))
		var before := FileAccess.get_file_as_string(store.path)
		var progress := store.load_progress()
		progress["muted"] = false
		var saved := store.save_progress(progress)
		check(not saved and not store.last_error.is_empty(), name_text + " permission denial returns false with a readable warning", store.last_error)
		check(FileAccess.get_file_as_string(store.path) == before, name_text + " denial preserves previous save byte-for-byte")
	var missing := _store(_path("missing-parent/progress.json"))
	check(not missing.save_progress(missing.defaults()) and not missing.last_error.is_empty(), "missing parent cannot be opened for writing", missing.last_error)
	var corrupt := _store(_path("backup/progress.json"))
	var corrupt_before := FileAccess.get_file_as_string(corrupt.path)
	var recovered_data := corrupt.load_progress()
	check(corrupt.recovered and not corrupt.last_error.is_empty(), "corrupt protected save enters recovery")
	check(not corrupt.save_progress(recovered_data) and not corrupt.last_error.is_empty() and FileAccess.get_file_as_string(corrupt.path) == corrupt_before, "backup denial refuses to overwrite corrupt original", corrupt.last_error)
	for name_text: String in ["write-small", "write-session"]:
		var store := _store(_path(name_text + "/progress.json"))
		var before := FileAccess.get_file_as_string(store.path)
		var progress := store.load_progress()
		progress["muted"] = false
		if name_text == "write-session":
			progress["session"] = sim.serialize_state(sim.new_game(4, 503))
		var saved := store.save_progress(progress)
		check(not saved and not store.last_error.is_empty(), name_text + " /dev/full write/flush failure is reported", "returned=" + str(saved) + ", last_error=" + store.last_error)
		# Never try to read a device if a failed write was wrongly renamed.
		check(not saved and FileAccess.get_file_as_string(store.path) == before, name_text + " failure keeps old regular save bytes")
	var unreadable := _store(_path("read/progress.json"))
	var probe := FileAccess.open(unreadable.path, FileAccess.READ)
	check(probe == null, "read-denial fixture genuinely cannot be opened (DAC bypass disabled)")
	if probe != null:
		probe.close()
	var data := unreadable.load_progress()
	check(data == unreadable.defaults() and not unreadable.last_error.is_empty(), "unreadable existing save yields defaults and a readable warning", unreadable.last_error)
	var was_saved := unreadable.save_progress(data)
	check(not was_saved or not _backups(unreadable.path).is_empty(), "saving after unreadable load cannot destroy the only progress copy", "returned=" + str(was_saved) + ", backups=" + str(_backups(unreadable.path)) + ", last_error=" + unreadable.last_error)

func _version_probe() -> void:
	var versions := {"version-null": null, "version-array": [], "version-object": {}}
	if not versions.has(mode):
		check(false, "known audit mode", mode)
		return
	var store := _store(_path("progress.json"))
	_write(store.path, JSON.stringify({"version": versions[mode], "unlocked": 4, "stars": {"4": 3}}))
	print("BEGIN malformed version probe ", mode)
	var loaded: Variant = store.load_progress()
	check(loaded == store.defaults() and store.recovered and not store.last_error.is_empty(), "malformed version handled without runtime error: " + mode, "loaded=" + str(loaded) + ", last_error=" + store.last_error)
	print("END malformed version probe ", mode)
