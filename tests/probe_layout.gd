extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1200,820)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	for _i: int in range(10):
		await process_frame
	game._show_rules()
	for _i: int in range(8):
		await process_frame
	for name: String in ["close_rules"]:
		var b: Control = game.buttons[name]
		print("BUTTON ",name," ",b.get_global_rect())
		var parent: Node = b.get_parent()
		while parent != null:
			if parent is Control:
				print("ANCESTOR ",parent.get_class()," ",parent.get_global_rect()," min=",parent.get_combined_minimum_size())
			parent = parent.get_parent()
	quit()
