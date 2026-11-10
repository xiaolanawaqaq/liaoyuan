extends SceneTree

const Store := preload("res://scripts/save_store.gd")
const S := preload("res://scripts/sim.gd")
const C := preload("res://scripts/challenge_sim.gd")
var passed := 0
var failed := 0
var directory := ""

func check(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error("FAIL " + name)

func fixture(store, data: Dictionary) -> Dictionary:
	var file := FileAccess.open(store.path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	return store.load_progress()

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="):
			directory = arg.trim_prefix("--evidence=")
	if not directory.is_absolute_path() or directory.contains("..") or DirAccess.dir_exists_absolute(directory):
		push_error("Store tests need a unique non-existent absolute --evidence path, e.g. /tmp/liaoyuan-qa/store-<id>")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(directory)
	var store = Store.new()
	store.path = directory.path_join("store.json")
	var old := {"version":2,"unlocked":2,"stars":{"0":3,"1":2},"best":{"0":{"saved":.8,"turns":6}},"session":S.new().new_game(2,307),"muted":true,"tutorial_done":true}
	var restored: Dictionary = fixture(store, old)
	check(restored["stars"] == old["stars"] and restored["unlocked"] == 2, "legacy campaign progress compatible")
	check(S.new().deserialize_state(restored["session"]) == old["session"], "legacy midgame state retained")
	check(restored["challenge_best"] == 0 and restored["challenge_session"].is_empty() and restored["active_mode"] == "campaign", "missing challenge fields get safe defaults")
	var campaign_before: Dictionary = restored["session"].duplicate(true)
	var stars_before: Dictionary = restored["stars"].duplicate(true)
	store.record_challenge(restored, 4200, 2)
	store.record_challenge(restored, 400, 1)
	check(restored["challenge_best"] == 4200 and restored["challenge_best_sectors"] == 2, "challenge records monotone")
	check(restored["stars"] == stars_before and restored["session"] == campaign_before and restored["unlocked"] == 2, "challenge cannot overwrite campaign save or unlocks")
	var challenge = C.new()
	var root_seed := 12345
	var challenge_state: Dictionary = challenge.new_challenge(challenge.seed_for_sector(root_seed,2))
	restored["challenge_session"] = {"root":root_seed,"sector":2,"completed":1,"score":4200,"state":challenge.serialize_state(challenge_state)}
	restored["active_mode"] = "challenge"
	check(store.save_progress(restored), "separate sessions save atomically")
	var again = Store.new()
	again.path = store.path
	var roundtrip: Dictionary = again.load_progress()
	var restored_envelope: Dictionary = roundtrip["challenge_session"]
	check(roundtrip["active_mode"] == "challenge" and int(restored_envelope["root"]) == root_seed and int(restored_envelope["sector"]) == 2 and int(restored_envelope["completed"]) == 1 and int(restored_envelope["score"]) == 4200 and challenge.deserialize_state(restored_envelope["state"]) == challenge_state, "challenge envelope roundtrip")
	check(roundtrip["session"] == campaign_before and roundtrip["stars"] == stars_before, "two session types remain isolated")
	for invalid: Variant in [null, true, "42", [], {}, -1, 2.5, INF, NAN, 1e30]:
		var corrupt: Dictionary = old.duplicate(true)
		corrupt["challenge_best"] = invalid
		corrupt["challenge_best_sectors"] = invalid
		var safe: Dictionary = fixture(store, corrupt)
		check(safe["challenge_best"] == 0 and safe["challenge_best_sectors"] == 0, "invalid challenge record rejected " + str(invalid))
		check(safe["stars"] == stars_before, "bad challenge metadata retains campaign " + str(invalid))
	for invalid: Variant in [null, true, 99, "competitive", []]:
		var corrupt: Dictionary = old.duplicate(true)
		corrupt["active_mode"] = invalid
		corrupt["challenge_session"] = invalid
		var safe: Dictionary = fixture(store, corrupt)
		check(safe["active_mode"] == "campaign" and safe["challenge_session"].is_empty(), "malformed mode and session rejected " + str(invalid))
	print("V030 STORE RESULTS: %d passed, %d failed" % [passed,failed])
	quit(1 if failed else 0)
