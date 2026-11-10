extends SceneTree

func _initialize() -> void:
	var texture: Texture2D = load("res://assets/icon.svg")
	if texture == null:
		push_error("icon.svg not loadable")
		quit(1)
		return
	var base: Image = texture.get_image()
	base.convert(Image.FORMAT_RGBA8)
	for size: int in [192, 432]:
		var img: Image = base.duplicate() as Image
		img.resize(size, size, Image.INTERPOLATE_LANCZOS)
		var path := "res://assets/launcher-%d.png" % size
		img.save_png(ProjectSettings.globalize_path(path))
		print("saved ", path, " ", img.get_width(), "x", img.get_height())
	quit(0)
