extends "res://scripts/sim.gd"

const GENERATOR_VERSION := 1
var _configured_seed := 0
var _definition: Dictionary = {}
var _bridges: Array[Vector2i] = []

func seed_for_sector(root_seed: int, sector: int) -> int:
	var base := posmod(root_seed, 100000000)
	var mixed := posmod(base * 1103515245 + maxi(1, sector) * 12345, 715827000)
	return mixed * 3 + mini(maxi(sector, 1), 3) - 1

func new_challenge(seed: int) -> Dictionary:
	return new_game(0, clampi(seed, 1, 2147483646))

func level_definition(level_index: int, seed: int = 1) -> Dictionary:
	if level_index != 0:
		return {}
	_configure(seed)
	return _definition

func level_info(state: Dictionary) -> Dictionary:
	_configure(int(state["seed"]))
	return _definition

func _wind_at(_level_index: int, turn: int) -> int:
	var winds: Array = _definition["winds"]
	return int(winds[clampi(turn - 1, 0, winds.size() - 1)])

func _transition(state: Dictionary) -> Dictionary:
	_configure(int(state["seed"]))
	return super._transition(state)

func witness(seed: int) -> Array:
	_configure(seed)
	var actions: Array[Dictionary] = []
	for point: Vector2i in _bridges:
		var tile: String = _definition["map"][point.y].substr(point.x, 1)
		if tile == "T":
			actions.append({"tool":"axe", "c":point.x, "r":point.y})
		actions.append({"tool":"shovel", "c":point.x, "r":point.y})
	var turns: Array = []
	while not actions.is_empty():
		var turn_actions: Array = []
		for _i: int in range(3):
			if not actions.is_empty():
				turn_actions.append(actions.pop_front())
		turns.append(turn_actions)
	return turns

func _configure(seed: int) -> void:
	seed = clampi(seed, 1, 2147483646)
	if seed == _configured_seed:
		return
	_configured_seed = seed
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var stage := seed % 3 + 1
	var barrier := rng.randi_range(5, 7)
	var gap_start := rng.randi_range(2, 5)
	var gap_count := stage + 1
	var mirrored := rng.randi_range(0, 1) == 1
	var rows: Array[String] = []
	for r: int in ROWS:
		var line := ""
		for c: int in COLS:
			var symbol := "#" if r == 0 or r == ROWS - 1 or c == 0 or c == COLS - 1 else "."
			if symbol == ".":
				if c == barrier:
					symbol = "~"
				elif c > barrier:
					symbol = "T" if rng.randf() < .82 else ","
				elif c <= 2:
					symbol = "T" if rng.randf() < .7 else ","
				else:
					symbol = "," if rng.randf() < .28 else "."
			line += symbol
		rows.append(line)
	_bridges.clear()
	for r: int in range(gap_start, gap_start + gap_count):
		var symbol := "." if stage == 1 else ("T" if rng.randf() < .5 else ",")
		rows[r] = _set_symbol(rows[r], barrier, symbol)
		_bridges.append(Vector2i(barrier, r))
	var hut_column := COLS - 3
	rows[gap_start] = _set_symbol(rows[gap_start], hut_column, "H")
	if stage >= 2:
		rows[mini(8, gap_start + gap_count)] = _set_symbol(rows[mini(8, gap_start + gap_count)], hut_column, "H")
	var ignites: Array[Vector2i] = [Vector2i(1, gap_start), Vector2i(2, gap_start + gap_count - 1)]
	if stage == 3:
		ignites.append(Vector2i(1, gap_start + 1))
	var winds: Array[int] = []
	for turn: int in range(24):
		var direction: int = 2 if turn < 4 else int([2, 3, 1][rng.randi_range(0, 2)])
		winds.append(6 if direction == 2 and mirrored else (5 if direction == 3 and mirrored else (7 if direction == 1 and mirrored else direction)))
	if mirrored:
		for r: int in ROWS:
			rows[r] = rows[r].reverse()
		for i: int in _bridges.size():
			_bridges[i].x = COLS - 1 - _bridges[i].x
		for i: int in ignites.size():
			ignites[i].x = COLS - 1 - ignites[i].x
	_definition = {
		"name":"巡护 · 难度 %d" % stage, "seed":seed, "ap":3, "par":24,
		"wind":winds[0], "winds":winds, "map":rows, "ignites":ignites,
		"goal":"保住所有房屋；火烧尽后继续巡护下一片林地",
		"brief":"河岸、树桥和风序由编号生成。相同编号始终是同一局。",
		"tip":"借水岸封住所有桥口。树桥要先斧后铲；先保护靠近火线的格子。"
	}

func _set_symbol(line: String, column: int, symbol: String) -> String:
	return line.substr(0, column) + symbol + line.substr(column + 1)
