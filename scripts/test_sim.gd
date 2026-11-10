extends SceneTree

const SimScript := preload("res://scripts/sim.gd")
const SOLUTIONS_PATH := "res://tests/solutions.json"
var sim: LiaoyuanSim
var passed := 0
var failed := 0
var solution_records: Array = []
var victories: Array[Dictionary] = []
var defeats: Array[Dictionary] = []

func ok(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func same(actual: Variant, expected: Variant, label: String) -> void:
	ok(actual == expected, label)
	if actual != expected:
		print("  expected: ", expected, "\n  actual:   ", actual)

func _init() -> void:
	sim = SimScript.new()
	print("[Godot 4] Liaoyuan deterministic simulation tests")
	_test_maps()
	_test_tools()
	_test_heat()
	_test_water()
	_test_undo()
	_test_saves()
	_test_campaign()
	_test_scoring()
	_test_stress()
	print("RESULT: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _json_only(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return true
		TYPE_FLOAT:
			return is_finite(float(value))
		TYPE_ARRAY:
			for item: Variant in value:
				if not _json_only(item):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if not key is String or not _json_only(value[key]):
					return false
			return true
	return false

func _roundtrip(state: Dictionary, label: String) -> void:
	var before := sim.clone_state(state)
	var encoded := sim.serialize_state(state)
	ok(not encoded.is_empty(), label + " serializes")
	same(state, before, label + " save is pure")
	if encoded.is_empty():
		return
	ok(_json_only(encoded), label + " contains JSON values only")
	var decoded := sim.deserialize_state(JSON.parse_string(JSON.stringify(encoded)))
	same(decoded, state, label + " JSON roundtrip")
	encoded["cells"][0]["variant"] = -1.0
	same(state, before, label + " saved cells do not alias live cells")

func _test_maps() -> void:
	print("[1] Maps, metadata, initialization, deterministic seeds")
	same(sim.COLS, 14, "14 columns")
	same(sim.ROWS, 10, "10 rows")
	same(sim.LEVELS.size(), 5, "five campaign levels")
	same(sim.DIRS.size(), 8, "eight directions")
	same(sim.WET_TICKS, 3, "water lasts three resolutions")
	same(sim.TOOL_COSTS, {"shovel": 1, "axe": 1, "water": 1}, "tool costs")
	ok(sim.new_game(-1).is_empty() and sim.new_game(5).is_empty(), "invalid level rejected")
	same(sim.new_game(0, 0)["seed"], 1, "zero seed normalized")
	for level_index in sim.LEVELS.size():
		var level: Dictionary = sim.LEVELS[level_index]
		var label := "L%d" % (level_index + 1)
		for key: String in ["name", "goal", "brief", "tip"]:
			ok(level.has(key) and not str(level[key]).is_empty(), label + " metadata " + key)
		for key: String in ["par", "ap", "seed"]:
			ok(level.has(key) and int(level[key]) > 0, label + " metadata " + key)
		same(level["map"].size(), sim.ROWS, label + " row count")
		for row: String in level["map"]:
			same(row.length(), sim.COLS, label + " row width")
			for c in row.length():
				ok(sim.CHAR_TO_TILE.has(row.substr(c, 1)), label + " valid map tile")
		var state := sim.new_game(level_index, int(level["seed"]))
		same(state, sim.new_game(level_index, int(level["seed"])), label + " exact same-seed replay")
		for key: String in ["level", "ap", "ap_max", "turn", "wind", "forecast", "cells", "status", "reason", "huts", "hut_alive", "init_fuel", "burnt_fuel", "danger"]:
			ok(state.has(key), label + " stable state API " + key)
		same(state["cells"].size(), sim.COLS * sim.ROWS, label + " cell count")
		same(state["turn"], 1, label + " starts in planning turn one")
		same(state["status"], "playing", label + " starts playing")
		same(state["ap"], level["ap"], label + " starting AP")
		same(state["wind"], level["winds"][0], label + " imminent wind")
		same(state["forecast"].size(), 3, label + " three future winds")
		ok(int(state["huts"]) > 0, label + " houses exist")
		same(state["hut_alive"], state["huts"], label + " houses start intact")
		same(sim.burning_count(state), level["ignites"].size(), label + " specified initial fires")
		var count := 0
		var value := 0
		for cell: Dictionary in state["cells"]:
			for key: String in ["tile", "burn", "wet", "variant", "heat", "threshold", "cleared"]:
				ok(cell.has(key), label + " cell API " + key)
			var tile := int(cell["tile"])
			same(cell["threshold"], sim.HEAT_THRESHOLDS[tile], label + " threshold matches tile")
			value += int(sim.TILE_DEF[tile]["value"])
			if int(sim.TILE_DEF[tile]["value"]) > 0:
				count += 1
		same(state["init_fuel"], count, label + " initial fuel cells")
		same(state["init_value"], value, label + " weighted vegetation total")
		var preview := sim.forecast_next(state)
		ok(preview["threatened_huts"].is_empty(), label + " no immediate unavoidable house loss")
		same(state["danger"], preview["ignited"], label + " danger is exact")
		_roundtrip(state, label + " initial save")

func _reject(state: Dictionary, c: int, r: int, tool: String, label: String) -> void:
	var before := sim.clone_state(state)
	var check := sim.can_apply(state, c, r, tool)
	ok(not bool(check["ok"]) and not str(check.get("why", "")).is_empty(), label + " explains invalid action")
	same(state, before, label + " can_apply is pure")
	var result := sim.apply_tool(state, c, r, tool)
	ok(not bool(result["ok"]), label + " rejected")
	same(state, before, label + " invalid action leaves state unchanged")

func _act(state: Dictionary, c: int, r: int, tool: String, label: String) -> void:
	var before := sim.clone_state(state)
	var check := sim.can_apply(state, c, r, tool)
	ok(bool(check["ok"]), label + " is legal: " + str(check.get("why", "")))
	same(state, before, label + " validation is pure")
	var result := sim.apply_tool(state, c, r, tool)
	ok(bool(result["ok"]), label + " applied: " + str(result.get("why", "")))
	if not bool(result["ok"]):
		return
	same(state["ap"], int(before["ap"]) - 1, label + " costs exactly 1 AP")
	same(state["actions_used"], int(before["actions_used"]) + 1, label + " action counted once")
	same(state["turn"], before["turn"], label + " planning does not advance time")
	same(state["wind"], before["wind"], label + " planning does not advance wind")
	same(state["forecast"], before["forecast"], label + " planning preserves future winds")
	same(state["danger"], sim.forecast_next(state)["ignited"], label + " preview refreshes immediately")

func _test_tools() -> void:
	print("[2] Tool costs, targets, invalid actions, budgets")
	var state := sim.new_game(0, 103)
	for coords: Vector2i in [Vector2i(-1, 4), Vector2i(14, 4), Vector2i(3, -1), Vector2i(3, 10)]:
		_reject(state, coords.x, coords.y, "shovel", "out of bounds %s" % coords)
	_reject(state, 5, 3, "hose", "unknown tool")
	_reject(state, 5, 3, "", "empty tool")
	for tool: String in ["shovel", "axe", "water"]:
		_reject(state, 1, 4, tool, "burning tree + " + tool)
		_reject(state, 0, 0, tool, "rock + " + tool)
		_reject(state, 0, 1, tool, "lake + " + tool)
	_reject(state, 7, 2, "shovel", "shovel cannot clear tree in one action")
	_reject(state, 5, 3, "axe", "axe cannot dig grass")
	_reject(state, 2, 4, "axe", "shrub uses shovel not axe")
	_reject(state, 10, 4, "axe", "axe cannot destroy house")
	_reject(state, 10, 4, "shovel", "shovel cannot destroy house")
	var initial_value := int(state["init_value"])
	_act(state, 7, 2, "axe", "axe tree")
	var index := sim.cell_index(7, 2)
	same(state["cells"][index]["tile"], sim.GRASS, "axe leaves flammable grass")
	same(state["cells"][index]["threshold"], 3, "axed grass uses grass threshold")
	same(state["cleared_value"], 2, "axe removes two vegetation points")
	_act(state, 7, 2, "shovel", "shovel axed tree")
	same(state["cells"][index]["tile"], sim.FIREBREAK, "two actions make a tree firebreak")
	same(state["cells"][index]["threshold"], 0, "firebreak cannot heat or burn")
	same(state["cleared_value"], 3, "tree removal loses all three points")
	same(state["init_value"], initial_value, "clearing never lowers scoring denominator")
	_reject(state, 7, 2, "water", "water cannot target firebreak")
	_act(state, 2, 4, "shovel", "shovel shrub")
	same(state["cleared_value"], 5, "shrub removal costs two vegetation points")
	same(state["ap"], 0, "AP exhausted")
	_reject(state, 10, 4, "water", "zero AP cannot protect house")
	sim.end_turn(state)
	same(state["ap"], state["ap_max"], "end turn replenishes AP")
	_act(state, 10, 4, "water", "one action before ending early")
	sim.end_turn(state)
	same(state["ap"], state["ap_max"], "unused AP does not accumulate")
	var hot := sim.new_game(0, 103)
	sim.end_turn(hot)
	var hot_index := sim.cell_index(2, 3)
	same(hot["cells"][hot_index]["heat"], 2, "hot grass stores heat")
	ok(hot["danger"].has(hot_index), "hot grass is forecast to ignite")
	_act(hot, 2, 3, "shovel", "dig hot grass")
	same(hot["cells"][hot_index]["heat"], 0, "shovel clears heat")
	ok(not hot["danger"].has(hot_index), "digging removes exact warning instantly")
	var hot_tree := sim.new_game(1, 211)
	sim.end_turn(hot_tree)
	var tree_index := sim.cell_index(2, 3)
	same(hot_tree["cells"][tree_index]["heat"], 2, "tree accumulates visible heat")
	_act(hot_tree, 2, 3, "axe", "axe hot tree")
	same(hot_tree["cells"][tree_index]["heat"], 0, "axe clears stored heat")

# Small controlled boards below are UNIT FIXTURES, not campaign solutions.
# Every campaign win and every scored result is produced by legal actions only.
func _unit_board(wind: int = 2) -> Dictionary:
	var state := sim.new_game(0, 103)
	for cell: Dictionary in state["cells"]:
		cell["tile"] = sim.ROCK
		cell["threshold"] = 0
		cell["burn"] = 0
		cell["heat"] = 0
		cell["wet"] = 0
		cell["cleared"] = 0
	state["wind"] = wind
	for key: String in ["init_fuel", "burnt_fuel", "init_value", "burnt_value", "cleared_value", "huts", "hut_alive"]:
		state[key] = 0
	return state

func _put(state: Dictionary, c: int, r: int, tile: int, burn: int = 0) -> void:
	var cell: Dictionary = state["cells"][sim.cell_index(c, r)]
	cell["tile"] = tile
	cell["threshold"] = sim.HEAT_THRESHOLDS[tile]
	cell["burn"] = burn
	var value := int(sim.TILE_DEF[tile]["value"])
	state["init_value"] = int(state["init_value"]) + value
	if value > 0:
		state["init_fuel"] = int(state["init_fuel"]) + 1
		if burn > 0:
			state["burnt_fuel"] = int(state["burnt_fuel"]) + 1
			state["burnt_value"] = int(state["burnt_value"]) + value
	if tile == sim.HUT:
		state["huts"] = int(state["huts"]) + 1
		state["hut_alive"] = int(state["hut_alive"]) + (0 if burn > 0 else 1)

func _test_heat() -> void:
	print("[3] Eight-neighbor heat, diagonal wind, cooling, simultaneous spread")
	for wind in 8:
		var state := _unit_board(wind)
		_put(state, 5, 5, sim.TREE, 4)
		for direction: Vector2i in sim.DIRS:
			_put(state, 5 + direction.x, 5 + direction.y, sim.GRASS)
		var before := sim.clone_state(state)
		var preview := sim.forecast_next(state)
		same(state, before, "wind%d forecast is pure" % wind)
		for direction: Vector2i in sim.DIRS:
			var index := sim.cell_index(5 + direction.x, 5 + direction.y)
			var wind_direction: Vector2i = sim.DIRS[wind]
			var expected := 2 if direction.x * wind_direction.x + direction.y * wind_direction.y > 0 else 1
			same(preview["incoming_heat"][index], expected, "wind%d direction%s contribution" % [wind, direction])
			same(preview["heat"][index], expected, "wind%d direction%s accumulation" % [wind, direction])
		ok(preview["ignited"].is_empty(), "one neighbor cannot ignite cold grass in one turn")
		same(sim.end_turn(state), preview, "directional preview equals event")
	var diagonal := _unit_board()
	_put(diagonal, 5, 5, sim.TREE, 4)
	_put(diagonal, 6, 6, sim.GRASS)
	_put(diagonal, 7, 7, sim.GRASS)
	_put(diagonal, 4, 5, sim.GRASS)
	sim.end_turn(diagonal)
	var diagonal_event := sim.end_turn(diagonal)
	ok(diagonal_event["ignited"].has(sim.cell_index(6, 6)), "diagonal fire crosses a corner without cardinal fuel")
	same(diagonal["cells"][sim.cell_index(6, 6)]["burn"], 2, "new fire keeps its entire burn lifetime")
	same(diagonal["cells"][sim.cell_index(7, 7)]["heat"], 0, "new fire does not chain in same resolution")
	same(diagonal["cells"][sim.cell_index(4, 5)]["heat"], 2, "upwind heat is slower but not zero")
	var third := sim.end_turn(diagonal)
	same(diagonal["cells"][sim.cell_index(7, 7)]["heat"], 2, "new fire spreads starting following turn")
	ok(third["ignited"].has(sim.cell_index(4, 5)), "three upwind ticks ignite grass")
	var combined := _unit_board()
	_put(combined, 5, 4, sim.TREE, 1)
	_put(combined, 5, 6, sim.TREE, 1)
	_put(combined, 6, 5, sim.TREE)
	var combined_forecast := sim.forecast_next(combined)
	same(combined_forecast["incoming_heat"][sim.cell_index(6, 5)], 4, "multiple sources add heat")
	same(combined_forecast["ignited"], [sim.cell_index(6, 5)], "tree ignites at exactly four heat")
	same(combined_forecast["exhausted"], [sim.cell_index(5, 4), sim.cell_index(5, 6)], "last-tick sources still spread before exhaustion")
	same(sim.end_turn(combined), combined_forecast, "simultaneous exhaustion/ignition preview exact")
	same(combined["cells"][sim.cell_index(6, 5)]["burn"], 4, "tree lifetime is four")
	same(combined["burnt_fuel"], 3, "burnt fuel counts newly ignited cells exactly once")
	same(combined["burnt_value"], 9, "burn loss is charged at ignition")
	for _i in 4:
		sim.end_turn(combined)
	same(combined["burnt_fuel"], 3, "exhaustion does not charge burn loss again")
	same(combined["cells"][sim.cell_index(6, 5)]["tile"], sim.ASH, "exhausted tree becomes ash")
	var cooling := _unit_board()
	_put(cooling, 5, 5, sim.TREE, 1)
	_put(cooling, 6, 5, sim.TREE)
	_put(cooling, 10, 1, sim.TREE, 4)
	var cooling_index := sim.cell_index(6, 5)
	sim.end_turn(cooling)
	same(cooling["cells"][cooling_index]["heat"], 2, "heat survives below threshold")
	sim.end_turn(cooling)
	same(cooling["cells"][cooling_index]["heat"], 1, "no input cools heat by one")
	sim.end_turn(cooling)
	same(cooling["cells"][cooling_index]["heat"], 0, "heat cools to zero, not negative")
	var hut := _unit_board()
	_put(hut, 5, 5, sim.TREE, 4)
	_put(hut, 6, 5, sim.HUT)
	sim.end_turn(hut)
	var hut_preview := sim.forecast_next(hut)
	same(hut_preview["threatened_huts"], [sim.cell_index(6, 5)], "house loss preview identifies exact house")
	same(hut_preview["status"], "lost", "preview predicts defeat")
	same(sim.end_turn(hut), hut_preview, "house forecast exactly matches loss")
	same(hut["hut_alive"], 0, "house is lost at ignition, not two turns later")

func _test_water() -> void:
	print("[4] Water immunity, expiry, refreshing, no extinguishing")
	for target: Array in [[5, 3, sim.GRASS], [2, 4, sim.SHRUB], [7, 2, sim.TREE], [10, 4, sim.HUT]]:
		var state := sim.new_game(0, 103)
		_act(state, int(target[0]), int(target[1]), "water", "water target %s" % target[2])
		var index := sim.cell_index(int(target[0]), int(target[1]))
		same(state["cells"][index]["wet"], 3, "water gives three full protected turns")
		_reject(state, int(target[0]), int(target[1]), "water", "same-turn duplicate water")
		sim.end_turn(state)
		_act(state, int(target[0]), int(target[1]), "water", "refresh partially spent water")
		same(state["cells"][index]["wet"], 3, "refresh restores duration to three")
	var hot := sim.new_game(0, 103)
	sim.end_turn(hot)
	_act(hot, 2, 3, "water", "water hot grass")
	var hot_index := sim.cell_index(2, 3)
	same(hot["cells"][hot_index]["heat"], 0, "water erases accumulated heat")
	ok(not hot["danger"].has(hot_index), "water immediately removes ignition warning")
	var state := _unit_board()
	_put(state, 5, 4, sim.TREE, 4)
	_put(state, 5, 6, sim.TREE, 4)
	_put(state, 6, 5, sim.GRASS)
	var target := sim.cell_index(6, 5)
	_act(state, 6, 5, "water", "unit fixture water")
	for turn in 3:
		var preview := sim.forecast_next(state)
		same(preview["incoming_heat"][target], 0, "wet target blocks all sources on protected turn %d" % (turn + 1))
		ok(not preview["ignited"].has(target), "wet target cannot ignite")
		same(sim.end_turn(state), preview, "wet forecast exact")
		same(state["cells"][target]["wet"], 2 - turn, "water countdown after protected turn %d" % (turn + 1))
		same(state["cells"][target]["heat"], 0, "water blocks accumulation, not just ignition")
	var dry_preview := sim.forecast_next(state)
	same(dry_preview["incoming_heat"][target], 4, "fourth resolution is no longer protected")
	ok(dry_preview["ignited"].has(target), "expiry can visibly expose a target to fire")
	same(sim.end_turn(state), dry_preview, "expiry forecast exact")
	_reject(state, 6, 5, "water", "water cannot extinguish an existing flame")
	var clearing := sim.new_game(1, 211)
	_act(clearing, 6, 3, "water", "wet tree before clearing")
	_act(clearing, 6, 3, "axe", "axe wet tree")
	same(clearing["cells"][sim.cell_index(6, 3)]["wet"], 3, "axe preserves protection on remaining grass")
	_act(clearing, 6, 3, "shovel", "shovel wet grass")
	same(clearing["cells"][sim.cell_index(6, 3)]["wet"], 0, "firebreak no longer needs water")

func _test_undo() -> void:
	print("[5] Clone isolation, repeatable planning undo, preview isolation")
	var state := sim.new_game(1, 211)
	var original := sim.clone_state(state)
	var snapshot := sim.clone_state(state)
	_act(state, 6, 3, "axe", "undo trial axe")
	_act(state, 6, 3, "shovel", "undo trial shovel")
	_act(state, 6, 4, "water", "undo trial water")
	same(snapshot, original, "all nested snapshot data survives planning mutations")
	var planned := sim.clone_state(state)
	var first_preview := sim.forecast_next(state)
	var first_event := sim.end_turn(state)
	var first_resolved := sim.clone_state(state)
	same(snapshot, original, "snapshot survives end_turn")
	state = sim.clone_state(snapshot)
	same(state, original, "undo restores AP, heat, wet, score, wind, and turn")
	_act(state, 6, 3, "axe", "replayed axe")
	_act(state, 6, 3, "shovel", "replayed shovel")
	_act(state, 6, 4, "water", "replayed water")
	same(state, planned, "same plan after undo is identical")
	same(sim.forecast_next(state), first_preview, "undo does not advance hidden randomness")
	same(sim.end_turn(state), first_event, "replayed resolution identical")
	same(state, first_resolved, "replayed resulting state identical")
	var before := sim.clone_state(state)
	var preview := sim.forecast_next(state)
	preview["heat"][0] = 900
	preview["wet"][0] = 900
	preview["burn"][0] = 900
	preview["incoming_heat"][0] = 900
	preview["forecast"][0] = 7
	preview["next_forecast"][0] = 7
	preview["ignited"].append(0)
	same(state, before, "caller-owned preview arrays cannot mutate simulation")
	var independent := sim.clone_state(state)
	independent["forecast"][0] = 7
	independent["danger"].append(0)
	independent["cells"][0]["variant"] = -99.0
	same(state, before, "clone deeply isolates arrays and dictionaries")

func _test_saves() -> void:
	print("[6] Untrusted save validation and continuation")
	for bad: Variant in [null, false, 7, 1.5, "save", [], {}]:
		ok(sim.deserialize_state(bad).is_empty(), "non-save JSON rejected")
	var initial := sim.new_game(0, 103)
	var edits: Array = [
		["schema_version", 2], ["level", -1], ["level", 5], ["seed", 0], ["seed", -1],
		["turn", 0], ["turn", 2.5], ["turn", 562], ["ap", -1], ["ap", 4], ["ap", "3"],
		["ap_max", 99], ["wind", 1], ["forecast", []], ["forecast", [2, 2, 7]],
		["status", "won"], ["status", "lost"], ["status", "other"], ["reason", "tampered"],
		["huts", 99], ["hut_alive", 0], ["init_fuel", 0], ["init_value", 0],
		["burnt_fuel", 0], ["burnt_value", 0], ["cleared_value", 1],
		["actions_used", -1], ["actions_used", 1], ["danger", [0]], ["cells", []],
		["turn", NAN], ["ap", INF]
	]
	for edit: Array in edits:
		var bad := sim.clone_state(initial)
		bad[edit[0]] = edit[1]
		ok(sim.deserialize_state(bad).is_empty(), "reject malformed field %s=%s" % edit)
	var extra := sim.clone_state(initial)
	extra["unexpected"] = []
	ok(sim.deserialize_state(extra).is_empty(), "unknown state fields rejected")
	var missing := sim.clone_state(initial)
	missing.erase("cells")
	ok(sim.deserialize_state(missing).is_empty(), "missing state fields rejected")
	var cell_edits: Array = [
		["tile", 99], ["tile", sim.HUT], ["burn", 1], ["burn", 999], ["wet", -1], ["wet", 4],
		["wet", 1], ["heat", 1], ["heat", 99], ["threshold", 3], ["cleared", 1],
		["variant", NAN], ["variant", INF], ["variant", "0.5"], ["variant", -1.0]
	]
	for edit: Array in cell_edits:
		var bad := sim.clone_state(initial)
		bad["cells"][0][edit[0]] = edit[1]
		ok(sim.deserialize_state(bad).is_empty(), "reject malformed cell %s=%s" % edit)
	var missing_cell := sim.clone_state(initial)
	missing_cell["cells"][0].erase("heat")
	ok(sim.deserialize_state(missing_cell).is_empty(), "missing cell field rejected")
	var wrong_cell := sim.clone_state(initial)
	# JSON-shaped untyped container permits arbitrary hostile element types.
	var raw: Dictionary = JSON.parse_string(JSON.stringify(wrong_cell))
	raw["cells"][0] = "not a cell"
	ok(sim.deserialize_state(raw).is_empty(), "non-object cell rejected without crashing")
	var extinguished := sim.clone_state(initial)
	extinguished["cells"][sim.cell_index(1, 4)]["burn"] = 0
	ok(sim.deserialize_state(extinguished).is_empty(), "starting fire cannot disappear from save")
	var burning_wet := sim.clone_state(initial)
	burning_wet["cells"][sim.cell_index(1, 4)]["wet"] = 1
	ok(sim.deserialize_state(burning_wet).is_empty(), "burning and wet are mutually exclusive")
	var changed_danger := sim.new_game(0, 103)
	sim.end_turn(changed_danger)
	changed_danger["danger"] = []
	ok(sim.deserialize_state(changed_danger).is_empty(), "stale exact warning rejected")
	var original := sim.new_game(3, 409)
	_act(original, 4, 2, "axe", "save continuation axe")
	_roundtrip(original, "mid-planning save")
	var restored := sim.deserialize_state(JSON.parse_string(JSON.stringify(sim.serialize_state(original))))
	if restored.is_empty():
		return
	_act(original, 4, 2, "shovel", "original continuation shovel")
	_act(restored, 4, 2, "shovel", "loaded continuation shovel")
	same(sim.end_turn(original), sim.end_turn(restored), "loaded turn resolves identically")
	same(original, restored, "loaded state stays identical")

func _resolve_checked(state: Dictionary, label: String, check_save: bool = true) -> Dictionary:
	var before := sim.clone_state(state)
	var preview := sim.forecast_next(state)
	same(sim.forecast_next(state), preview, label + " repeated forecast deterministic")
	same(state, before, label + " forecast never mutates state")
	same(state["danger"], preview["ignited"], label + " danger is exact next ignitions")
	var event := sim.end_turn(state)
	same(event, preview, label + " entire event exactly matches preview")
	same(event["spread"], event["ignited"].size(), label + " spread not double-counted")
	same(state["turn"], int(before["turn"]) + 1, label + " advances exactly one turn")
	same(state["ap"], state["ap_max"], label + " replenishes budget")
	same(state["wind"], before["forecast"][0], label + " announced wind becomes imminent wind")
	same(state["wind"], preview["next_wind"], label + " next wind exact")
	same(state["forecast"], preview["next_forecast"], label + " next forecast exact")
	same(state["forecast"][0], before["forecast"][1], label + " future wind queue shifts one")
	same(state["forecast"][1], before["forecast"][2], label + " future wind queue shifts two")
	same(state["status"], preview["status"], label + " outcome forecast exact")
	for i in state["cells"].size():
		var cell: Dictionary = state["cells"][i]
		for key: String in ["heat", "wet", "burn"]:
			same(cell[key], preview[key][i], label + " exact resulting %s at cell%d" % [key, i])
		if event["exhausted"].has(i):
			same(cell["tile"], sim.ASH, label + " exhausted cell is ash")
			same(cell["threshold"], 0, label + " ash threshold is zero")
	if check_save:
		_roundtrip(state, label + " save")
	return event

func _terminal_immutable(state: Dictionary, label: String) -> void:
	var before := sim.clone_state(state)
	var event := sim.end_turn(state)
	ok(bool(event["ignored"]), label + " end_turn ignored")
	ok(event["ignited"].is_empty() and event["exhausted"].is_empty() and event["threatened_huts"].is_empty(), label + " no post-end events")
	same(state, before, label + " no post-end mutation")
	same(sim.forecast_next(state), event, label + " terminal forecast is also inert")
	for tool: String in ["shovel", "axe", "water"]:
		_reject(state, 5, 3, tool, label + " post-end " + tool)
	same(state, before, label + " terminal scores immutable")
	_roundtrip(state, label + " terminal save")

func _test_campaign() -> void:
	print("[7] Real campaign solutions, no-defense threat, multi-seed replay")
	ok(FileAccess.file_exists(SOLUTIONS_PATH), "machine-readable solution file exists")
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOLUTIONS_PATH))
	if not document is Dictionary or not document.get("levels") is Array:
		ok(false, "solution JSON schema")
		return
	solution_records = document["levels"]
	same(solution_records.size(), 5, "one stored solution for each campaign level")
	for record: Dictionary in solution_records:
		var level := int(record["index"])
		var label := "L%d" % (level + 1)
		var state := sim.new_game(level, int(record["seed"]))
		var turns: Array = record["turns"]
		for turn in turns.size():
			ok(state["status"] == "playing", label + " solution reaches every recorded turn")
			for action: Dictionary in turns[turn]:
				_act(state, int(action["c"]), int(action["r"]), str(action["tool"]), label + " T%d %s(%d,%d)" % [turn + 1, action["tool"], action["c"], action["r"]])
				_roundtrip(state, label + " planned action")
			_resolve_checked(state, label + " defended T%d" % (turn + 1))
		var result := sim.stats(state)
		var expected: Dictionary = record["expected"]
		same(state["status"], "won", label + " wins only via apply_tool/end_turn")
		same(sim.burning_count(state), 0, label + " win requires every fire out")
		same(state["hut_alive"], state["huts"], label + " win keeps all houses")
		same(result["turn"], turns.size(), label + " no redundant post-victory turns in solution")
		same(result["turn"], int(expected["turns"]), label + " measured completion time")
		same(result["stars"], int(expected["stars"]), label + " three stars genuinely reachable")
		same(result["actions_used"], int(expected["actions"]), label + " measured action count")
		for key: String in ["init_value", "burnt_value", "cleared_value", "saved_value"]:
			same(result[key], int(expected[key]), label + " measured " + key)
		ok(int(result["turn"]) >= 6 and int(result["turn"]) <= 15, label + " short intentional level")
		ok(is_equal_approx(float(result["saved_fraction"]) + float(result["lost_fraction"]), 1.0), label + " score fractions add to one")
		same(result["loss_fraction"], result["lost_fraction"], label + " score alias")
		_terminal_immutable(state, label + " won")
		victories.append(sim.clone_state(state))
		var passive := sim.new_game(level, int(record["seed"]))
		var guard := 0
		while passive["status"] == "playing" and guard < 60:
			# Deliberately resolve even without defense (the old smoke test did not).
			_resolve_checked(passive, label + " passive T%d" % (guard + 1))
			guard += 1
		same(passive["status"], "lost", label + " no-defense run faces a real house threat")
		same(guard, int(expected["passive_loss_turn"]), label + " exact passive loss turn")
		ok(guard >= 4 and guard <= 15, label + " readable threat window, not instant or endless")
		same(sim.stats(passive)["stars"], 0, label + " genuine loss scores zero")
		ok(int(passive["hut_alive"]) < int(passive["huts"]), label + " loss has an actually ignited house")
		_terminal_immutable(passive, label + " lost")
		defeats.append(sim.clone_state(passive))
		for replay_seed in [1, 8675309, -7]:
			var replay := sim.new_game(level, replay_seed)
			for actions: Array in turns:
				for action: Dictionary in actions:
					ok(bool(sim.apply_tool(replay, int(action["c"]), int(action["r"]), str(action["tool"]))["ok"]), label + " seed-independent legal action")
				var forecast := sim.forecast_next(replay)
				same(sim.end_turn(replay), forecast, label + " seed-independent exact forecast")
			same(sim.stats(replay), result, label + " gameplay and score independent of cosmetic seed")
			_roundtrip(replay, label + " alternate-seed save")
		print("BALANCE L%d: win=%d turns, actions=%d, saved=%.2f%% (%d/%d), burnt=%d, cleared=%d, stars=%d; no-defense=lost T%d" % [level + 1, result["turn"], result["actions_used"], 100.0 * float(result["saved_fraction"]), result["saved_value"], result["init_value"], result["burnt_value"], result["cleared_value"], result["stars"], guard])

func _scored_axe_run(count: int) -> Dictionary:
	# L2's protected forest remains safe. Waste spare AP axing it to verify
	# that forest destruction cannot masquerade as conservation or earn stars.
	var record: Dictionary = solution_records[1]
	var state := sim.new_game(1, int(record["seed"]))
	var remaining := count
	for actions: Array in record["turns"]:
		for action: Dictionary in actions:
			_act(state, int(action["c"]), int(action["r"]), str(action["tool"]), "scoring base solution")
		for r in sim.ROWS:
			for c in range(7, sim.COLS):
				if remaining == 0 or int(state["ap"]) == 0:
					break
				var cell: Dictionary = state["cells"][sim.cell_index(c, r)]
				if int(cell["tile"]) == sim.TREE and int(cell["burn"]) == 0:
					var before := sim.stats(state)
					_act(state, c, r, "axe", "scoring unnecessary axe")
					var after := sim.stats(state)
					same(after["saved_value"], int(before["saved_value"]) - 2, "each unnecessary axe lowers conservation")
					same(after["init_value"], before["init_value"], "axe cannot shrink original denominator")
					remaining -= 1
		same(sim.end_turn(state)["ignored"], false, "scoring run resolves actual live turn")
	same(remaining, 0, "requested axe count actually applied")
	same(state["status"], "won", "scoring fixture wins naturally")
	_roundtrip(state, "scoring result save")
	return state

func _test_scoring() -> void:
	print("[8] Actual victories: 1/2/3-star scoring and anti-axe farming")
	if solution_records.size() != 5 or victories.size() != 5:
		ok(false, "campaign results required for scoring tests")
		return
	var base := sim.stats(victories[1])
	same(base["stars"], 3, "efficient real solution earns three stars")
	var two := sim.stats(_scored_axe_run(6))
	same(two["stars"], 2, "real victory with six wasteful axes drops to two stars")
	same(two["saved_value"], int(base["saved_value"]) - 12, "two-star score includes removed tree canopy")
	same(two["burnt_value"], base["burnt_value"], "scoring downgrade is from clearing, not extra fire")
	var one := sim.stats(_scored_axe_run(20))
	same(one["stars"], 1, "real victory with twenty wasteful axes drops to one star")
	same(one["saved_value"], int(base["saved_value"]) - 40, "one-star score includes all wasteful clearing")
	ok(float(base["saved_fraction"]) > float(two["saved_fraction"]) and float(two["saved_fraction"]) > float(one["saved_fraction"]), "more destruction never improves conservation")
	for state: Dictionary in victories:
		var result := sim.stats(state)
		ok(int(result["turn"]) <= int(result["par"]), "stored three-star solution beats par")
		ok(float(result["saved_fraction"]) >= float(result["three_star_saved"]), "stored three-star solution meets preservation target")
	for state: Dictionary in defeats:
		same(sim.stats(state)["stars"], 0, "every actual defeat scores zero")
	var late := sim.new_game(0, 103)
	for action: Dictionary in solution_records[0]["turns"][0]:
		_act(late, int(action["c"]), int(action["r"]), str(action["tool"]), "late run builds the same firebreak")
	sim.end_turn(late)
	_act(late, 1, 3, "water", "late run delays grass combustion")
	_act(late, 2, 3, "water", "late run staggers second grass combustion")
	var guard := 0
	while late["status"] == "playing" and guard < 30:
		_resolve_checked(late, "late real victory")
		guard += 1
	same(late["status"], "won", "late victory reached without editing state")
	var late_result := sim.stats(late)
	same(late_result["turn"], 9, "water delay naturally finishes after tutorial par of eight")
	same(late_result["saved_value"], sim.stats(victories[0])["saved_value"], "late and timely victories preserve identical vegetation")
	same(late_result["stars"], 2, "missing par caps otherwise three-star conservation at two")
	print("SCORING: L2 base=3 stars %.2f%%, +6 axes=2 stars %.2f%%, +20 axes=1 star %.2f%%; late L1=2 stars T%d" % [100.0 * float(base["saved_fraction"]), 100.0 * float(two["saved_fraction"]), 100.0 * float(one["saved_fraction"]), late_result["turn"]])

func _test_stress() -> void:
	print("[9] Deterministic adversarial plans and save-input stress")
	# The local chooser is test-only. No simulation RNG or package is used.
	var chooser := RandomNumberGenerator.new()
	chooser.seed = 20261006
	var plans := 0
	for level in sim.LEVELS.size():
		for trial in 4:
			var state := sim.new_game(level, 9000 + trial)
			var guard := 0
			while state["status"] == "playing" and guard < 60:
				var count := chooser.randi_range(0, int(state["ap_max"]))
				for _action in count:
					var choices: Array[Dictionary] = []
					for r in sim.ROWS:
						for c in sim.COLS:
							for tool: String in ["shovel", "axe", "water"]:
								if bool(sim.can_apply(state, c, r, tool)["ok"]):
									choices.append({"c": c, "r": r, "tool": tool})
					if choices.is_empty():
						break
					var choice: Dictionary = choices[chooser.randi_range(0, choices.size() - 1)]
					var before := sim.clone_state(state)
					var before_score := sim.stats(state)
					var result := sim.apply_tool(state, int(choice["c"]), int(choice["r"]), str(choice["tool"]))
					ok(bool(result["ok"]), "stress legal action succeeds")
					ok(float(sim.stats(state)["saved_fraction"]) <= float(before_score["saved_fraction"]), "stress actions cannot farm vegetation value")
					var planned := sim.clone_state(state)
					var replay := sim.clone_state(before)
					sim.apply_tool(replay, int(choice["c"]), int(choice["r"]), str(choice["tool"]))
					same(replay, planned, "stress undo/reapply identity")
					_roundtrip(state, "stress planned save")
				_resolve_checked(state, "stress L%d trial%d T%d" % [level + 1, trial, guard + 1])
				guard += 1
			ok(state["status"] != "playing", "stress plan resolves within finite guard")
			_terminal_immutable(state, "stress terminal")
			plans += 1
	# Reject malformed JSON-shaped data without exceptions or coercion to a game.
	var base := sim.new_game(0, 103)
	var cell_keys := ["tile", "burn", "wet", "heat", "threshold", "cleared", "variant"]
	for key: String in cell_keys:
		for value: Variant in [null, true, "wrong", [], {}, -999.0, 99999999.0]:
			var data: Dictionary = JSON.parse_string(JSON.stringify(base))
			data["cells"][0][key] = value
			ok(sim.deserialize_state(data).is_empty(), "hostile cell input rejected: " + key)
	for key: String in ["level", "seed", "ap", "turn", "forecast", "danger", "cells", "actions_used", "hut_alive", "burnt_value"]:
		for value: Variant in [null, true, "wrong", -999.0, 99999999.0]:
			var data: Dictionary = JSON.parse_string(JSON.stringify(base))
			data[key] = value
			ok(sim.deserialize_state(data).is_empty(), "hostile state input rejected: " + key)
	print("STRESS: %d independently generated legal campaigns; malformed save matrix rejected" % plans)
