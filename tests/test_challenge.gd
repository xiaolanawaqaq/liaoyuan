extends SceneTree

const Challenge := preload("res://scripts/challenge_sim.gd")
const Campaign := preload("res://scripts/sim.gd")
var passed := 0
var failed := 0

func check(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error("FAIL " + name)

func _initialize() -> void:
	var sim = Challenge.new()
	var maps := {}
	var winning_turns := []
	var losses := []
	for seed: int in range(1, 301):
		var state: Dictionary = sim.new_challenge(seed)
		var original: Dictionary = sim.clone_state(state)
		check(state == sim.new_challenge(seed), "same seed deterministic %d" % seed)
		maps[str(sim.level_info(state)["map"])] = true
		var plan: Array = sim.witness(seed)
		for actions: Array in plan:
			for action: Dictionary in actions:
				check(sim.can_apply(state, action["c"], action["r"], action["tool"])["ok"], "witness legal %d" % seed)
				check(sim.apply_tool(state, action["c"], action["r"], action["tool"])["ok"], "witness action %d" % seed)
				check(not sim.serialize_state(state).is_empty(), "midplanning serialization %d" % seed)
			var preview: Dictionary = sim.forecast_next(state)
			check(preview == sim.end_turn(state), "witness forecast event %d" % seed)
		for _turn: int in range(50):
			if state["status"] != "playing":
				break
			var preview: Dictionary = sim.forecast_next(state)
			check(preview == sim.end_turn(state), "empty forecast event %d" % seed)
		check(state["status"] == "won", "seeded challenge solvable %d" % seed)
		var result: Dictionary = sim.stats(state)
		check(result["stars"] >= 2, "conservation achievable %d saved=%f" % [seed,result["saved_fraction"]])
		winning_turns.append(result["turn"])
		var roundtrip: Dictionary = sim.deserialize_state(JSON.parse_string(JSON.stringify(state)))
		check(roundtrip == state, "challenge JSON restore %d" % seed)
		var idle: Dictionary = sim.clone_state(original)
		for _turn: int in range(50):
			if idle["status"] != "playing":
				break
			sim.end_turn(idle)
		check(idle["status"] == "lost", "no defense genuinely loses %d" % seed)
		losses.append(sim.stats(idle)["turn"])
		var snapshot: Dictionary = sim.clone_state(original)
		snapshot["cells"][0]["heat"] = 1
		check(original["cells"][0]["heat"] == 0, "clone detached %d" % seed)
		var wrong: Dictionary = sim.clone_state(original)
		wrong["seed"] = seed + 1
		check(sim.deserialize_state(wrong).is_empty(), "wrong procedural seed rejected %d" % seed)
	check(maps.size() > 200, "many genuinely distinct terrain maps")
	var a: Dictionary = sim.new_challenge(5)
	var b: Dictionary = sim.new_challenge(104)
	check(sim.forecast_next(a) == Challenge.new().forecast_next(a), "multi-state seed isolation A")
	check(sim.forecast_next(b) == Challenge.new().forecast_next(b), "multi-state seed isolation B")
	check(Campaign.new().new_game(0,103)["init_value"] == 132, "campaign initialization unchanged")
	print("CHALLENGE MAPS: ", maps.size(), " winner turns=", winning_turns.min(), "..", winning_turns.max(), " no-defense losses=", losses.min(), "..", losses.max())
	print("CHALLENGE RESULTS: %d passed, %d failed" % [passed,failed])
	quit(1 if failed else 0)
