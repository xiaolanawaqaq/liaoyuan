extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1200,820)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	for _i: int in range(8):
		await process_frame
	print("INITIAL root.size=",root.size," scale_size=",root.content_scale_size," viewport=",game.get_viewport_rect()," mobile=",game.mobile_layout)
	root.size = Vector2i(1200,600)
	for _i: int in range(15):
		await process_frame
	print("RESIZED root.size=",root.size," scale_size=",root.content_scale_size," viewport=",game.get_viewport_rect()," mobile=",game.mobile_layout)
	root.content_scale_size = Vector2i(1200,600)
	game.mobile_layout = true
	game._show_home()
	for _i: int in range(15):
		await process_frame
	print("COMPACT root.size=",root.size," scale_size=",root.content_scale_size," viewport=",game.get_viewport_rect()," mobile=",game.mobile_layout)
	for id: String in game.buttons:
		print("BUTTON ",id," ",game.buttons[id].get_global_rect())
	game._start_level(0)
	for _i: int in range(15):
		await process_frame
	print("GAME viewport=",game.get_viewport_rect())
	for id: String in game.buttons:
		print("BUTTON ",id," ",game.buttons[id].get_global_rect())
	root.remove_child(game)
	game.queue_free()
	await process_frame
	quit()
