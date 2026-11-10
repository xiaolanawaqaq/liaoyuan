class_name LiaoyuanSim
extends RefCounted

## Deterministic, scene-independent campaign simulation.
## wind is used by the IMMINENT resolution; forecast is the following three winds.
## State contains only JSON types. Preview and resolution share _transition().

const COLS := 14
const ROWS := 10
const WET_TICKS := 3
const FORECAST_COUNT := 3
const SAVE_VERSION := 1
const TOOL_COSTS := {"shovel": 1, "axe": 1, "water": 1}
const THREE_STAR_SAVED := 0.70
const TWO_STAR_SAVED := 0.45

const GRASS := 0
const SHRUB := 1
const TREE := 2
const ROCK := 3
const WATER := 4
const HUT := 5
const FIREBREAK := 6
const ASH := 7

const DIRS := [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)
]
const DIR_CH := ["↑", "↗", "→", "↘", "↓", "↙", "←", "↖"]
const DIR_NAMES := ["向北", "向东北", "向东", "向东南", "向南", "向西南", "向西", "向西北"]
const TILE_NAMES := ["草地", "灌木", "树木", "岩石", "水面", "房屋", "防火带", "灰烬"]
const TOOL_NAMES := {"shovel": "铁锹", "axe": "斧头", "water": "水壶"}
const HEAT_THRESHOLDS := [3, 3, 4, 0, 0, 4, 0, 0]
const TILE_DEF := [
	{"name": "草地", "threshold": 3, "burn_ticks": 2, "value": 1},
	{"name": "灌木", "threshold": 3, "burn_ticks": 3, "value": 2},
	{"name": "树木", "threshold": 4, "burn_ticks": 4, "value": 3},
	{"name": "岩石", "threshold": 0, "burn_ticks": 0, "value": 0},
	{"name": "水面", "threshold": 0, "burn_ticks": 0, "value": 0},
	{"name": "房屋", "threshold": 4, "burn_ticks": 2, "value": 0},
	{"name": "防火带", "threshold": 0, "burn_ticks": 0, "value": 0},
	{"name": "灰烬", "threshold": 0, "burn_ticks": 0, "value": 0},
]

# Wind schedules hold their last entry, rather than hiding a random roll.
# Maps intentionally use water/rock to frame short, readable fire corridors.
const LEVELS := [
	{
		"name": "初火 · 三格防线", "ap": 3, "par": 8, "seed": 103,
		"wind": 2, "winds": [2, 2, 2, 2, 2, 2, 2, 2],
		"goal": "守住一座房屋，让火自然燃尽",
		"brief": "东风把火推向林地。橙色边框是本轮必定起火的格子；工具会立即改变预报。",
		"tip": "在狭口竖着铲掉三格草地，连接上下水岸。斜角也会传火，别漏掉边缘。",
		"ignites": [Vector2i(1, 4)],
		"map": [
			"##############", "~~~~~~.......~", "~~~~~~.TTTTT.~", "~......TTTTT.~",
			"~T,,...TTTHT.~", "~......TTTTT.~", "~~~~~~.TTTTT.~", "~~~~~~.TTTTT.~",
			"~~~~~~.......~", "##############"
		]
	},
	{
		"name": "树桥 · 两步开路", "ap": 3, "par": 10, "seed": 211,
		"wind": 2, "winds": [2, 2, 2, 3, 3, 2, 2, 2],
		"goal": "切断两格树桥，保护两座房屋",
		"brief": "水面只留下两格树木相连。斧头留下可燃的草地，防火带还需要再铲一次。",
		"tip": "每棵树要斧、铲两步。先完成一格，再用下回合的行动完成另一格。",
		"ignites": [Vector2i(1, 4)],
		"map": [
			"##############", "~~~~~~~......~", "~#....~.TTTT.~", "~.T...T.TTTH.~",
			"~T....T.TTTT.~", "~.,...~.TTTT.~", "~#....~.TTTH.~", "~~~~~~~.TTTT.~",
			"~~~~~~~......~", "##############"
		]
	},
	{
		"name": "转风 · 留住南岸", "ap": 2, "par": 10, "seed": 307,
		"wind": 2, "winds": [2, 2, 4, 4, 3, 3, 2, 2, 4, 4],
		"goal": "在风转向前封住东、南两个出口",
		"brief": "两回合后东风转为南风。只有两点行动，必须同时照看东侧树林和南岸小屋。",
		"tip": "先封近火的东出口，再补南出口。看后续风向，而不是等房屋亮起危险边框。",
		"ignites": [Vector2i(5, 2)],
		"map": [
			"##############", "~~.,.........~", "~~...T..TTHT.~", "~~.,....TTTT.~",
			"~~...~~.TTTT.~", "~.....~.TTTT.~", "~.TTT.~.TTTT.~", "~.THT.~.TTTT.~",
			"~.....~......~", "##############"
		]
	},
	{
		"name": "两线 · 借水争时", "ap": 2, "par": 10, "seed": 409,
		"wind": 2, "winds": [2, 2, 6, 6, 2, 2, 6, 6, 2, 2, 6, 6],
		"goal": "用两点行动调度两条相向火线",
		"brief": "左侧是树桥，右侧是草桥。水不能灭火，但能让未燃的格子连续三轮完全免疫。",
		"tip": "先断一棵树桥，给另一棵浇水争取时间；转身挖右侧三格，再回来斧、铲湿树。",
		"ignites": [Vector2i(3, 2), Vector2i(10, 7)],
		"map": [
			"#####TTTT#####", "~...~.TT.~~~~~", "~T.TTTHTT~~~~~", "~...TTTTT~~~~~",
			"~~~~~TTTT~~~~~", "~~~~~TTTT~~~~~", "~~~~~TTTT....~", "~~~~~TTHT.T.T~",
			"~~~~~.TT.....~", "#####TTTT#####"
		]
	},
	{
		"name": "林场 · 三处守望", "ap": 3, "par": 11, "seed": 503,
		"wind": 2, "winds": [2, 2, 6, 6, 3, 3, 2, 2, 6, 6, 2, 2],
		"goal": "保护三座房屋，并保留至少七成植被争取三星",
		"brief": "三处火源包围林场。树木值三份植被；无谓砍树与火烧一样会降低保存率。",
		"tip": "用水保住西侧两棵树桥，铲断相邻草桥；集中斧、铲切断东侧，再按湿润倒计时补水。",
		"ignites": [Vector2i(3, 2), Vector2i(3, 7), Vector2i(12, 4)],
		"map": [
			"##############", "~T..~T....T~~~", "~..TTTTHTTT~~~", "~T...TTTTTTT.T",
			"~~~~~TTTTTT,T.", "~~~~~TTTHTT..T", "~T..TTTTTTT~~~", "~..T.TTHTTT~~~",
			"~T..~T....T~~~", "##############"
		]
	}
]

const CHAR_TO_TILE := {".": GRASS, ",": SHRUB, "T": TREE, "#": ROCK, "~": WATER, "H": HUT}

func cell_index(c: int, r: int) -> int:
	return r * COLS + c

func in_bounds(c: int, r: int) -> bool:
	return c >= 0 and c < COLS and r >= 0 and r < ROWS

func level_definition(level_index: int, _seed: int = 1) -> Dictionary:
	if level_index < 0 or level_index >= LEVELS.size():
		return {}
	return LEVELS[level_index]

func level_info(state: Dictionary) -> Dictionary:
	return level_definition(int(state["level"]), int(state["seed"]))

func new_game(level_index: int, seed: int = 1) -> Dictionary:
	var level: Dictionary = level_definition(level_index, seed)
	if level.is_empty():
		return {}
	var visual_seed := posmod(seed, 2147483647)
	if visual_seed == 0:
		visual_seed = 1
	var cells: Array[Dictionary] = []
	var fuel_count := 0
	var vegetation_value := 0
	var huts := 0
	for r in ROWS:
		for c in COLS:
			var tile: int = CHAR_TO_TILE[level["map"][r].substr(c, 1)]
			cells.append({
				"tile": tile, "burn": 0, "wet": 0, "heat": 0,
				"threshold": HEAT_THRESHOLDS[tile], "cleared": 0,
				"variant": _variant(visual_seed, cell_index(c, r))
			})
			var value := int(TILE_DEF[tile]["value"])
			vegetation_value += value
			if value > 0:
				fuel_count += 1
			if tile == HUT:
				huts += 1
	var state := {
		"schema_version": SAVE_VERSION, "level": level_index, "seed": visual_seed,
		"ap_max": int(level["ap"]), "ap": int(level["ap"]), "turn": 1,
		"wind": _wind_at(level_index, 1), "forecast": _forecast_at(level_index, 1),
		"cells": cells, "status": "playing", "reason": "",
		"init_fuel": fuel_count, "burnt_fuel": 0,
		"init_value": vegetation_value, "burnt_value": 0, "cleared_value": 0,
		"actions_used": 0, "huts": huts, "hut_alive": huts, "danger": []
	}
	for ignite: Vector2i in level["ignites"]:
		_ignite(state, cell_index(ignite.x, ignite.y))
	_refresh_danger(state)
	return state

func _variant(seed: int, index: int) -> float:
	return float(posmod(seed * 1103515245 + index * 12345, 65536)) / 65535.0

func _wind_at(level_index: int, turn: int) -> int:
	var winds: Array = LEVELS[level_index]["winds"]
	return int(winds[clampi(turn - 1, 0, winds.size() - 1)])

func _forecast_at(level_index: int, turn: int) -> Array[int]:
	var forecast: Array[int] = []
	for offset in range(1, FORECAST_COUNT + 1):
		forecast.append(_wind_at(level_index, turn + offset))
	return forecast

func clone_state(state: Dictionary) -> Dictionary:
	return state.duplicate(true)

func can_apply(state: Dictionary, c: int, r: int, tool: String) -> Dictionary:
	if state.get("status", "") != "playing":
		return {"ok": false, "why": "本局已结束"}
	if not in_bounds(c, r):
		return {"ok": false, "why": "超出地图"}
	if not TOOL_COSTS.has(tool):
		return {"ok": false, "why": "未知工具"}
	if int(state["ap"]) < int(TOOL_COSTS[tool]):
		return {"ok": false, "why": "行动点不足，结束回合后补满"}
	var cell: Dictionary = state["cells"][cell_index(c, r)]
	if int(cell["burn"]) > 0:
		return {"ok": false, "why": "正在燃烧：工具不能灭火，请保护前方未燃的格子"}
	var tile := int(cell["tile"])
	if tool == "shovel" and (tile == GRASS or tile == SHRUB):
		return {"ok": true, "why": "", "cost": TOOL_COSTS[tool]}
	if tool == "axe" and tile == TREE:
		return {"ok": true, "why": "", "cost": TOOL_COSTS[tool]}
	if tool == "water" and int(HEAT_THRESHOLDS[tile]) > 0:
		if int(cell["wet"]) == WET_TICKS:
			return {"ok": false, "why": "已湿润三回合，本轮无需重复浇水"}
		return {"ok": true, "why": "", "cost": TOOL_COSTS[tool]}
	return {"ok": false, "why": "这个工具在这里不起作用"}

func apply_tool(state: Dictionary, c: int, r: int, tool: String) -> Dictionary:
	var result := can_apply(state, c, r, tool)
	if not bool(result["ok"]):
		return result
	var cell: Dictionary = state["cells"][cell_index(c, r)]
	var old_value := int(TILE_DEF[int(cell["tile"])]["value"])
	if tool == "shovel":
		cell["tile"] = FIREBREAK
		cell["wet"] = 0
	elif tool == "axe":
		cell["tile"] = GRASS
	else:
		cell["wet"] = WET_TICKS
	cell["heat"] = 0
	cell["threshold"] = HEAT_THRESHOLDS[int(cell["tile"])]
	var removed := old_value - int(TILE_DEF[int(cell["tile"])]["value"])
	cell["cleared"] = int(cell["cleared"]) + removed
	state["cleared_value"] = int(state["cleared_value"]) + removed
	state["ap"] = int(state["ap"]) - int(TOOL_COSTS[tool])
	state["actions_used"] = int(state["actions_used"]) + 1
	_refresh_danger(state)
	return result

func _ignite(state: Dictionary, index: int) -> void:
	var cell: Dictionary = state["cells"][index]
	var tile := int(cell["tile"])
	cell["burn"] = int(TILE_DEF[tile]["burn_ticks"])
	cell["heat"] = 0
	if tile == HUT:
		state["hut_alive"] = int(state["hut_alive"]) - 1
	else:
		# Loss is charged at ignition, not when the flame animation expires.
		state["burnt_fuel"] = int(state["burnt_fuel"]) + 1
		state["burnt_value"] = int(state["burnt_value"]) + int(TILE_DEF[tile]["value"])

func _refresh_danger(state: Dictionary) -> void:
	state["danger"] = forecast_next(state)["ignited"]

func forecast_next(state: Dictionary) -> Dictionary:
	return _transition(state)

func _transition(state: Dictionary) -> Dictionary:
	var cells: Array = state["cells"]
	var heat: Array[int] = []
	var incoming: Array[int] = []
	var wet: Array[int] = []
	var burn: Array[int] = []
	var ignited: Array[int] = []
	var exhausted: Array[int] = []
	var threatened_huts: Array[int] = []
	for cell: Dictionary in cells:
		heat.append(int(cell["heat"]))
		incoming.append(0)
		wet.append(int(cell["wet"]))
		burn.append(int(cell["burn"]))
	var active: bool = state["status"] == "playing"
	var wind := int(state["wind"])
	var next_wind := _wind_at(int(state["level"]), int(state["turn"]) + 1) if active else wind
	var next_forecast: Array = _forecast_at(int(state["level"]), int(state["turn"]) + 1) if active else state["forecast"].duplicate()
	var status := str(state["status"])
	if active:
		var wind_direction: Vector2i = DIRS[wind]
		# Read only the original fire set: a new flame never chains this turn.
		for i in cells.size():
			if int(cells[i]["burn"]) <= 0:
				continue
			var c := i % COLS
			@warning_ignore("integer_division")
			var r := i / COLS
			for direction: Vector2i in DIRS:
				var nc := c + direction.x
				var nr := r + direction.y
				if not in_bounds(nc, nr):
					continue
				var ni := cell_index(nc, nr)
				var neighbour: Dictionary = cells[ni]
				if int(neighbour["burn"]) > 0 or int(neighbour["wet"]) > 0 or int(neighbour["threshold"]) == 0:
					continue
				var downwind := direction.x * wind_direction.x + direction.y * wind_direction.y > 0
				incoming[ni] += 2 if downwind else 1
		var next_burning := 0
		for i in cells.size():
			var cell: Dictionary = cells[i]
			var tile := int(cell["tile"])
			wet[i] = maxi(0, wet[i] - 1)
			if int(cell["burn"]) > 0:
				heat[i] = 0
				burn[i] -= 1
				if burn[i] == 0:
					exhausted.append(i)
			elif int(cell["wet"]) > 0 or int(cell["threshold"]) == 0:
				heat[i] = 0
			else:
				heat[i] = heat[i] + incoming[i] if incoming[i] > 0 else maxi(0, heat[i] - 1)
				if heat[i] >= int(cell["threshold"]):
					ignited.append(i)
					heat[i] = 0
					burn[i] = int(TILE_DEF[tile]["burn_ticks"])
					if tile == HUT:
						threatened_huts.append(i)
			if burn[i] > 0:
				next_burning += 1
		if not threatened_huts.is_empty():
			status = "lost"
		elif next_burning == 0:
			status = "won"
	return {
		"ignored": not active, "ignited": ignited, "exhausted": exhausted,
		"threatened_huts": threatened_huts, "heat": heat, "incoming_heat": incoming,
		"wet": wet, "burn": burn, "wind": wind, "next_wind": next_wind,
		"forecast": state["forecast"].duplicate(), "next_forecast": next_forecast,
		"wind_changed": next_wind != wind, "hut_lost": not threatened_huts.is_empty(),
		"spread": ignited.size(), "status": status
	}

func end_turn(state: Dictionary) -> Dictionary:
	var event := _transition(state)
	if bool(event["ignored"]):
		return event
	for i in state["cells"].size():
		var cell: Dictionary = state["cells"][i]
		cell["heat"] = event["heat"][i]
		cell["wet"] = event["wet"][i]
		cell["burn"] = event["burn"][i]
	for i: int in event["exhausted"]:
		state["cells"][i]["tile"] = ASH
		state["cells"][i]["threshold"] = 0
	for i: int in event["ignited"]:
		_ignite(state, i)
	state["status"] = event["status"]
	if state["status"] == "lost":
		state["reason"] = "房屋被点燃了。重试时留意斜角与湿润倒计时。"
	elif state["status"] == "won":
		state["reason"] = "火已燃尽，所有房屋安全。"
	state["turn"] = int(state["turn"]) + 1
	state["wind"] = int(event["next_wind"])
	state["forecast"] = event["next_forecast"].duplicate()
	state["ap"] = int(state["ap_max"])
	_refresh_danger(state)
	return event

func burning_count(state: Dictionary) -> int:
	var count := 0
	for cell: Dictionary in state["cells"]:
		if int(cell["burn"]) > 0:
			count += 1
	return count

func stats(state: Dictionary) -> Dictionary:
	var level: Dictionary = level_info(state)
	var total := int(state["init_value"])
	var burnt := int(state["burnt_value"])
	var cleared := int(state["cleared_value"])
	var lost_fraction := clampf(float(burnt + cleared) / float(maxi(1, total)), 0.0, 1.0)
	var saved_fraction := 1.0 - lost_fraction
	var turns := int(state["turn"]) - 1
	var stars := 0
	if state["status"] == "won":
		if saved_fraction + 0.000001 >= THREE_STAR_SAVED and turns <= int(level["par"]):
			stars = 3
		elif saved_fraction + 0.000001 >= TWO_STAR_SAVED:
			stars = 2
		else:
			stars = 1
	return {
		"turn": turns, "saved_fraction": saved_fraction, "lost_fraction": lost_fraction,
		"loss_fraction": lost_fraction, "burnt_fraction": float(burnt) / float(maxi(1, total)),
		"cleared_fraction": float(cleared) / float(maxi(1, total)),
		"saved_value": maxi(0, total - burnt - cleared), "init_value": total,
		"burnt_value": burnt, "cleared_value": cleared, "actions_used": state["actions_used"],
		"hut_alive": state["hut_alive"], "huts": state["huts"],
		"stars": stars, "par": int(level["par"]),
		"three_star_saved": THREE_STAR_SAVED, "two_star_saved": TWO_STAR_SAVED
	}

func serialize_state(state: Dictionary) -> Dictionary:
	# Validate on both sides of storage; returned data never aliases the caller.
	return deserialize_state(state)

func _integer_between(value: Variant, low: int, high: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return is_finite(number) and number >= float(low) and number <= float(high) and floorf(number) == number

func _same_keys(data: Dictionary, template: Dictionary) -> bool:
	if data.size() != template.size():
		return false
	for key: Variant in template:
		if not data.has(key):
			return false
	return true

func _valid_tile_change(original: int, tile: int, cleared: int) -> bool:
	match original:
		GRASS, SHRUB:
			return (tile == original or tile == ASH) and cleared == 0 or tile == FIREBREAK and cleared == int(TILE_DEF[original]["value"])
		TREE:
			return tile == TREE and cleared == 0 or tile == GRASS and cleared == 2 or tile == FIREBREAK and cleared == 3 or tile == ASH and (cleared == 0 or cleared == 2)
		_:
			return tile == original and cleared == 0

func deserialize_state(data: Variant) -> Dictionary:
	# Arbitrary JSON input must pass structural AND game-invariant checks.
	# JSON numbers may be floats; normalize integer fields before returning.
	if not data is Dictionary:
		return {}
	if not _integer_between(data.get("level"), 0, LEVELS.size() - 1):
		return {}
	if not _integer_between(data.get("seed"), 1, 2147483646):
		return {}
	var result := new_game(int(data["level"]), int(data["seed"]))
	if not _same_keys(data, result):
		return {}
	for key: String in ["schema_version", "level", "seed", "ap_max", "init_fuel", "init_value", "huts"]:
		if not _integer_between(data[key], int(result[key]), int(result[key])):
			return {}
	if not _integer_between(data["turn"], 1, COLS * ROWS * 4 + 1):
		return {}
	if not _integer_between(data["ap"], 0, int(result["ap_max"])):
		return {}
	var turn := int(data["turn"])
	var current_actions := int(result["ap_max"]) - int(data["ap"])
	if not _integer_between(data["actions_used"], current_actions, (turn - 1) * int(result["ap_max"]) + current_actions):
		return {}
	if not data["status"] is String or not ["playing", "won", "lost"].has(data["status"]):
		return {}
	var status: String = data["status"]
	var reason := ""
	if status == "won":
		reason = "火已燃尽，所有房屋安全。"
	elif status == "lost":
		reason = "房屋被点燃了。重试时留意斜角与湿润倒计时。"
	if not data["reason"] is String or data["reason"] != reason:
		return {}
	if status != "playing" and (current_actions != 0 or turn == 1):
		return {}
	var expected_wind := _wind_at(int(result["level"]), turn)
	if not _integer_between(data["wind"], expected_wind, expected_wind):
		return {}
	var expected_forecast := _forecast_at(int(result["level"]), turn)
	if not data["forecast"] is Array or data["forecast"].size() != FORECAST_COUNT:
		return {}
	for i in FORECAST_COUNT:
		if not _integer_between(data["forecast"][i], expected_forecast[i], expected_forecast[i]):
			return {}
	if not data["cells"] is Array or data["cells"].size() != COLS * ROWS:
		return {}
	var burnt_value := 0
	var burnt_fuel := 0
	var cleared_value := 0
	var burning := 0
	var hut_alive := int(result["huts"])
	var minimum_actions := 0
	for i in COLS * ROWS:
		var source: Variant = data["cells"][i]
		var cell: Dictionary = result["cells"][i]
		if not source is Dictionary or not _same_keys(source, cell):
			return {}
		if not _integer_between(source["tile"], GRASS, ASH) or not _integer_between(source["cleared"], 0, 3):
			return {}
		var original := int(cell["tile"])
		var tile := int(source["tile"])
		var cleared := int(source["cleared"])
		var threshold := int(HEAT_THRESHOLDS[tile])
		if not _valid_tile_change(original, tile, cleared):
			return {}
		if not _integer_between(source["threshold"], threshold, threshold):
			return {}
		if not _integer_between(source["burn"], 0, int(TILE_DEF[tile]["burn_ticks"])):
			return {}
		if not _integer_between(source["wet"], 0, WET_TICKS) or not _integer_between(source["heat"], 0, maxi(0, threshold - 1)):
			return {}
		var burn := int(source["burn"])
		var wet := int(source["wet"])
		var heat := int(source["heat"])
		if (burn > 0 and (wet > 0 or heat > 0)) or (wet > 0 and heat > 0) or (threshold == 0 and wet > 0):
			return {}
		# Starting fires cannot be cleared or watered away.
		if int(cell["burn"]) > 0 and not (burn > 0 and tile == original or tile == ASH and cleared == 0):
			return {}
		if typeof(source["variant"]) != TYPE_INT and typeof(source["variant"]) != TYPE_FLOAT:
			return {}
		if not is_finite(float(source["variant"])) or not is_equal_approx(float(source["variant"]), float(cell["variant"])):
			return {}
		if burn > 0:
			burning += 1
		if original == HUT and burn > 0:
			if burn != int(TILE_DEF[HUT]["burn_ticks"]):
				return {}
			hut_alive -= 1
		elif burn > 0 or tile == ASH:
			burnt_fuel += 1
			burnt_value += int(TILE_DEF[original]["value"]) - cleared
		cleared_value += cleared
		minimum_actions += 2 if original == TREE and tile == FIREBREAK else (1 if cleared > 0 else 0)
		if wet > 0:
			minimum_actions += 1
		for key: String in ["tile", "burn", "wet", "heat", "threshold", "cleared"]:
			cell[key] = int(source[key])
	if int(data["actions_used"]) < minimum_actions:
		return {}
	for pair: Array in [["burnt_fuel", burnt_fuel], ["burnt_value", burnt_value], ["cleared_value", cleared_value], ["hut_alive", hut_alive]]:
		if not _integer_between(data[pair[0]], int(pair[1]), int(pair[1])):
			return {}
		result[pair[0]] = pair[1]
	if status == "playing" and (burning == 0 or hut_alive != int(result["huts"])):
		return {}
	if status == "won" and (burning != 0 or hut_alive != int(result["huts"])):
		return {}
	if status == "lost" and hut_alive == int(result["huts"]):
		return {}
	for key: String in ["turn", "ap", "actions_used"]:
		result[key] = int(data[key])
	result["status"] = status
	result["reason"] = reason
	result["wind"] = expected_wind
	result["forecast"] = expected_forecast
	_refresh_danger(result)
	if not data["danger"] is Array or data["danger"].size() != result["danger"].size():
		return {}
	for i in result["danger"].size():
		var expected := int(result["danger"][i])
		if not _integer_between(data["danger"][i], expected, expected):
			return {}
	return result
