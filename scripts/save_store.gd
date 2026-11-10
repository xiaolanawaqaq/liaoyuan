extends RefCounted

const SAVE_VERSION := 2
const DEFAULT_PATH := "user://progress-v2.json"

var path: String = DEFAULT_PATH
var last_error := ""
var recovered := false

func defaults() -> Dictionary:
	return {
		"version": SAVE_VERSION, "unlocked": 0, "stars": {}, "best": {},
		"muted": false, "reduced_motion": false, "high_contrast": false,
		"tutorial_done": false, "session": {}, "active_mode": "campaign",
		"challenge_best": 0, "challenge_best_sectors": 0, "challenge_session": {}
	}

func load_progress() -> Dictionary:
	var result: Dictionary = defaults()
	if not FileAccess.file_exists(path):
		return result
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		recovered = true
		last_error = "无法读取存档；本次仍可正常游玩，但不会覆盖原存档。"
		return result
	var raw: Variant = JSON.parse_string(file.get_as_text())
	if not raw is Dictionary:
		recovered = true
		last_error = "存档无法解析，已保留原文件。"
		return result
	var version_value: Variant = raw.get("version", -1)
	if not _is_integer(version_value) or int(version_value) != SAVE_VERSION:
		recovered = true
		last_error = "旧版或损坏的存档已忽略，不影响开始新游戏。"
		return result
	if _is_integer(raw.get("unlocked")):
		result["unlocked"] = clampi(int(raw["unlocked"]), 0, 4)
	for key: String in ["muted", "reduced_motion", "high_contrast", "tutorial_done"]:
		if raw.get(key) is bool:
			result[key] = raw[key]
	if raw.get("stars") is Dictionary:
		for key: String in ["0", "1", "2", "3", "4"]:
			if _is_integer(raw["stars"].get(key)):
				result["stars"][key] = clampi(int(raw["stars"][key]), 0, 3)
	if raw.get("best") is Dictionary:
		for key: String in ["0", "1", "2", "3", "4"]:
			var entry: Variant = raw["best"].get(key)
			if entry is Dictionary and _is_number(entry.get("saved")) and _is_integer(entry.get("turns")):
				result["best"][key] = {"saved": clampf(float(entry["saved"]), 0, 1), "turns": clampi(int(entry["turns"]), 1, 999)}
	if raw.get("session") is Dictionary:
		result["session"] = raw["session"].duplicate(true)
	if raw.get("challenge_session") is Dictionary:
		result["challenge_session"] = raw["challenge_session"].duplicate(true)
	if raw.get("active_mode") is String and raw["active_mode"] in ["campaign", "challenge"]:
		result["active_mode"] = raw["active_mode"]
	for key: String in ["challenge_best", "challenge_best_sectors"]:
		if _is_integer(raw.get(key)) and float(raw[key]) >= 0 and float(raw[key]) <= 100000000:
			result[key] = int(raw[key])
	for i: int in range(4):
		if int(result["stars"].get(str(i), 0)) > 0:
			result["unlocked"] = maxi(int(result["unlocked"]), i + 1)
	return result

func save_progress(data: Dictionary) -> bool:
	last_error = ""
	if recovered and FileAccess.file_exists(path):
		var backup: String = path + ".recovered-" + str(int(Time.get_unix_time_from_system()))
		var backup_error := DirAccess.copy_absolute(path, backup)
		if backup_error != OK:
			# The original file cannot even be copied (e.g. unreadable). Keep
			# refusing to overwrite it so progress already earned is never lost.
			last_error = "无法备份旧存档，本次未覆盖它。"
			return false
		recovered = false
	var temporary: String = path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = "存档写入失败，请检查目录权限和磁盘空间。"
		return false
	file.store_string(JSON.stringify(data))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		last_error = "存档写入失败；上一次存档仍被保留。"
		return false
	var move_error := DirAccess.rename_absolute(temporary, path)
	if move_error != OK:
		last_error = "无法替换存档；上一次存档仍被保留。"
		return false
	return true

func record_win(progress: Dictionary, level_index: int, result: Dictionary) -> void:
	var key := str(level_index)
	progress["stars"][key] = maxi(int(progress["stars"].get(key, 0)), int(result["stars"]))
	progress["unlocked"] = maxi(int(progress["unlocked"]), mini(level_index + 1, 4))
	progress["tutorial_done"] = true
	var previous: Dictionary = progress["best"].get(key, {})
	var saved: float = float(result["saved_fraction"])
	var turns: int = int(result["turn"])
	if previous.is_empty() or saved > float(previous["saved"]) or (is_equal_approx(saved, float(previous["saved"])) and turns < int(previous["turns"])):
		progress["best"][key] = {"saved": saved, "turns": turns}
	progress["session"] = {}

func record_challenge(progress: Dictionary, score: int, sectors: int) -> void:
	progress["challenge_best"] = maxi(int(progress.get("challenge_best", 0)), clampi(score, 0, 100000000))
	progress["challenge_best_sectors"] = maxi(int(progress.get("challenge_best_sectors", 0)), clampi(sectors, 0, 1000000))

func _is_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _is_integer(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		var f: float = value
		return is_finite(f) and f == floorf(f)
	return false
