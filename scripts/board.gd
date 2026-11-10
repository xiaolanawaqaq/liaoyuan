extends Control

signal cell_chosen(cell: Vector2i)
signal cell_hovered(cell: Vector2i)

const S := preload("res://scripts/sim.gd")
const UI_FONT := preload("res://assets/interface_font.tres")
const INK := Color("#12252a")
const GRASS := Color("#385a49")
const RUST := Color("#f4ae67")

var state: Dictionary = {}
var forecast: Dictionary = {}
var hover_cell := Vector2i(-1, -1)
var selected_tool := "shovel"
var show_forecast := true
var reduced_motion := false
var high_contrast := false
var interactive := true
var inspect_only := false
var tutorial_cells: Array[Vector2i] = []
var font: Font
var time := 0.0
var flash_time := 0.0
var flash_cells: Array = []
var last_drag_cell := Vector2i(-1, -1)
var active_touch := -1
var particles: Array[Dictionary] = []
var cosmetic_rng := RandomNumberGenerator.new()
var hover_valid := true
var board_rect := Rect2()
var cell_size := 40.0
var draw_scale := 1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	font = UI_FONT
	cosmetic_rng.seed = 7241
	mouse_exited.connect(_clear_hover)
	resized.connect(queue_redraw)

func _process(delta: float) -> void:
	if not visible or state.is_empty():
		return
	time += delta
	flash_time = maxf(0.0, flash_time - delta)
	if not reduced_motion:
		for particle: Dictionary in particles:
			particle["age"] = float(particle["age"]) + delta
			particle["pos"] = Vector2(particle["pos"]) + Vector2(particle["speed"]) * delta
		particles = particles.filter(func(p: Dictionary) -> bool: return float(p["age"]) < float(p["life"]))
		if particles.size() < 100:
			var wind: Vector2 = Vector2(S.DIRS[int(state["wind"])])
			for i: int in range(state["cells"].size()):
				if int(state["cells"][i]["burn"]) > 0 and cosmetic_rng.randf() < delta * 2.5:
					particles.append({
						"pos": Vector2(i % S.COLS + .5, floorf(float(i) / S.COLS) + .35),
						"speed": Vector2(wind.x * .3, wind.y * .2 - .5),
						"age": 0.0, "life": cosmetic_rng.randf_range(.6, 1.5),
						"size": cosmetic_rng.randf_range(1, 2.4)
					})
	queue_redraw()

func present(new_state: Dictionary, new_forecast: Dictionary) -> void:
	state = new_state
	forecast = new_forecast
	queue_redraw()

func show_transition(event: Dictionary) -> void:
	flash_cells = event.get("ignited", []).duplicate()
	flash_time = .42
	queue_redraw()

func clear_effects() -> void:
	particles.clear()
	flash_cells.clear()
	flash_time = 0.0
	active_touch = -1
	_clear_hover()

func geometry() -> Rect2:
	cell_size = floorf(minf((size.x - 36) / S.COLS, (size.y - 32) / S.ROWS))
	cell_size = maxf(cell_size, 8)
	draw_scale = cell_size / 48.0
	board_rect = Rect2((size - Vector2(S.COLS, S.ROWS) * cell_size) * .5, Vector2(S.COLS, S.ROWS) * cell_size)
	return board_rect

func cell_center(cell: Vector2i) -> Vector2:
	geometry()
	return board_rect.position + (Vector2(cell) + Vector2(.5, .5)) * cell_size

func position_cell(pos: Vector2) -> Vector2i:
	geometry()
	if not board_rect.has_point(pos):
		return Vector2i(-1, -1)
	return Vector2i(floori((pos.x - board_rect.position.x) / cell_size), floori((pos.y - board_rect.position.y) / cell_size))

func _choose(cell: Vector2i) -> void:
	hover_cell = cell
	cell_hovered.emit(cell)
	if cell.x >= 0:
		cell_chosen.emit(cell)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if not interactive or state.is_empty():
		return
	if event is InputEventScreenTouch:
		if event.pressed and active_touch == -1:
			active_touch = event.index
			var cell := position_cell(event.position)
			last_drag_cell = cell
			_choose(cell)
		elif not event.pressed and event.index == active_touch:
			active_touch = -1
			last_drag_cell = Vector2i(-1, -1)
		accept_event()
		return
	if event is InputEventScreenDrag:
		if event.index == active_touch:
			var cell := position_cell(event.position)
			if cell != hover_cell:
				hover_cell = cell
				cell_hovered.emit(cell)
			if not inspect_only and cell.x >= 0 and cell != last_drag_cell:
				last_drag_cell = cell
				_choose(cell)
		accept_event()
		return
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMouseMotion:
		var cell := position_cell(event.position)
		if cell != hover_cell:
			hover_cell = cell
			cell_hovered.emit(cell)
		if not inspect_only and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and cell.x >= 0 and cell != last_drag_cell:
			last_drag_cell = cell
			_choose(cell)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var cell := position_cell(event.position)
			last_drag_cell = cell
			_choose(cell)
		else:
			last_drag_cell = Vector2i(-1, -1)
		accept_event()

func _clear_hover() -> void:
	if active_touch != -1:
		return
	hover_cell = Vector2i(-1, -1)
	last_drag_cell = Vector2i(-1, -1)
	cell_hovered.emit(hover_cell)
	queue_redraw()

func _draw() -> void:
	if state.is_empty() or font == null:
		return
	geometry()
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("#152d30")
	panel.set_corner_radius_all(12)
	panel.shadow_color = Color(0, 0, 0, .3)
	panel.shadow_size = 7
	panel.shadow_offset = Vector2(0, 5)
	draw_style_box(panel, Rect2(Vector2.ZERO, size))
	draw_rect(board_rect.grow(2), Color("#0e2224"))
	for row: int in range(S.ROWS):
		for col: int in range(S.COLS):
			var index: int = row * S.COLS + col
			if index >= state["cells"].size():
				continue
			_draw_tile(col, row, state["cells"][index], index)
	for i: int in range(S.COLS):
		var x: float = board_rect.position.x + (i + .5) * cell_size
		_center_text(Vector2(x, board_rect.position.y - 6), String.chr(65 + i), 10, Color("#8dada3"))
	for i: int in range(S.ROWS):
		_center_text(Vector2(board_rect.position.x - 10, board_rect.position.y + (i + .59) * cell_size), str(i + 1), 10, Color("#8dada3"))
	if not reduced_motion:
		for particle: Dictionary in particles:
			var p: Vector2 = board_rect.position + Vector2(particle["pos"]) * cell_size
			if board_rect.grow(5).has_point(p):
				var alpha: float = 1.0 - float(particle["age"]) / float(particle["life"])
				draw_circle(p, float(particle["size"]), Color(1, .66, .27, alpha))
	for cell: Vector2i in tutorial_cells:
		var highlight := Rect2(board_rect.position + Vector2(cell) * cell_size, Vector2.ONE * cell_size).grow(-3)
		var pulse: float = .6 if reduced_motion else .45 + sin(time * 2.5) * .18
		draw_rect(highlight, Color(.58,.84,.74,pulse*.3))
		draw_rect(highlight, Color(.64,.93,.8,pulse), false, 2)
	if interactive and hover_cell.x >= 0:
		var hover_rect := Rect2(board_rect.position + Vector2(hover_cell) * cell_size, Vector2.ONE * cell_size).grow(-1)
		var outline := Color("#f5ead4") if hover_valid else Color("#ee6e64")
		draw_rect(hover_rect, Color(outline, .12))
		draw_rect(hover_rect, outline, false, 2.0)
		var corner := 8.0
		for point: Vector2 in [hover_rect.position, hover_rect.end]:
			var sign_dir := 1 if point == hover_rect.position else -1
			draw_line(point, point + Vector2(corner * sign_dir, 0), outline, 3)
			draw_line(point, point + Vector2(0, corner * sign_dir), outline, 3)

func _draw_tile(col: int, row: int, cell: Dictionary, index: int) -> void:
	var rect := Rect2(board_rect.position + Vector2(col, row) * cell_size, Vector2.ONE * cell_size).grow(-.65)
	var tile: int = int(cell["tile"])
	var variant: float = float(cell.get("variant", .5))
	var origin: Vector2 = rect.position
	var center: Vector2 = rect.get_center()
	var s: float = cell_size
	var shade: float = (variant - .5) * .055
	var ground: Color = GRASS.lightened(shade) if shade > 0 else GRASS.darkened(-shade)
	match tile:
		S.TREE: ground = Color("#304e40").lightened(variant * .06)
		S.SHRUB: ground = Color("#405944").lightened(variant * .08)
		S.ROCK: ground = Color("#344447").lightened(variant * .05)
		S.WATER: ground = Color("#245961").lightened(variant * .08)
		S.FIREBREAK: ground = Color("#977951").lightened(variant * .04)
		S.ASH: ground = Color("#37403b").lightened(variant * .05)
		S.HUT: ground = Color("#5c6047")
	if int(cell["burn"]) > 0:
		ground = ground.lerp(Color("#573426"), .62)
	draw_rect(rect, ground)
	if tile == S.GRASS or tile == S.TREE or tile == S.SHRUB:
		for k: int in range(3):
			var x: float = .15 + fposmod(variant * 3.7 + k * .27, .67)
			var y: float = .14 + fposmod(variant * 5.3 + k * .31, .68)
			var stem := origin + Vector2(x, y) * s
			draw_line(stem, stem + Vector2(-2, -4) * draw_scale, Color("#759263"), 1)
			draw_line(stem, stem + Vector2(2, -3) * draw_scale, Color("#5d794f"), 1)
	match tile:
		S.TREE:
			_tree(center + Vector2(0, -s * .08), s, variant, int(cell["burn"]) > 0)
		S.SHRUB:
			draw_circle(center + Vector2(1, 8) * draw_scale, s * .26, Color(0, 0, 0, .14))
			for k: int in range(3):
				draw_circle(center + Vector2((k - 1) * 7, 1 - (k % 2) * 4) * draw_scale, s * .16, Color("#76955a").darkened(k * .055))
		S.ROCK:
			var rock := PackedVector2Array([center + Vector2(-.31,.17)*s, center+Vector2(-.3,-.12)*s, center+Vector2(-.08,-.3)*s, center+Vector2(.23,-.26)*s, center+Vector2(.35,.09)*s, center+Vector2(.11,.26)*s])
			draw_colored_polygon(rock, Color("#6f7d79"))
			draw_colored_polygon(PackedVector2Array([rock[0], rock[1], rock[2], center+Vector2(.04,.0)*s]), Color("#87908a"))
			draw_line(center+Vector2(-.08,-.3)*s, center+Vector2(.12,.08)*s, Color("#a1a69b"), 1.4)
		S.WATER:
			for k: int in range(3):
				var offset: float = sin(time * 1.2 + col + row + k) * 2.0 if not reduced_motion else 0.0
				var p := origin + Vector2(.18 * s + offset, (.27 + k * .21) * s)
				draw_line(p, p + Vector2(s * .48, 0), Color("#50928f"), 1.2)
		S.FIREBREAK:
			draw_rect(Rect2(origin + Vector2(0,s*.7), Vector2(s-1,s*.26)), Color("#77603f"))
			for k: int in range(3):
				var p := origin + Vector2(s * .16, s * (.26 + k * .23))
				draw_line(p, p+Vector2(s*.66, -s*.09), Color("#b69c72"), 1.5)
		S.ASH:
			draw_line(center + Vector2(-.22,.2)*s, center+Vector2(.13,-.22)*s, Color("#202d2a"), 2)
			draw_line(center + Vector2(-.05,-.06)*s, center+Vector2(.29,.12)*s, Color("#202d2a"), 2)
		S.HUT:
			_house(center, s)
	if show_forecast and int(cell["heat"]) > 0 and int(cell["burn"]) == 0:
		var count: int = mini(int(cell["heat"]), 4)
		for k: int in range(count):
			draw_circle(origin + Vector2(6 + k * 5, 6) * draw_scale, 1.65 * draw_scale, Color("#efbf73"))
	if int(cell["wet"]) > 0:
		draw_rect(rect, Color(.2, .7, .85, .15))
		draw_rect(rect.grow(-1), Color("#81ced0"), false, 1.2)
		var badge := Rect2(rect.end - Vector2(22,20) * draw_scale, Vector2(20,18) * draw_scale)
		draw_rect(badge, Color("#163a48"))
		_center_text(badge.get_center() + Vector2(0,4*draw_scale), str(cell["wet"]), maxi(11, int(12*draw_scale)), Color("#bcf4f0"))
	if int(cell["burn"]) > 0:
		_fire(center, s, col + row * 2.17)
		for k: int in range(int(cell["burn"])):
			draw_rect(Rect2(origin+Vector2(5+k*6, s-6), Vector2(4,2.5)), Color("#f7d790"))
	if show_forecast and forecast.get("ignited", []).has(index):
		var alpha: float = .9 if reduced_motion else .78 + sin(time * 3) * .12
		var warning := Color("#ffa55f") if not high_contrast else Color("#fff1bb")
		draw_rect(rect.grow(-1), Color(warning, alpha), false, 2)
		for k: int in range(3):
			var p := rect.position + Vector2(3 + k * 6, s - 5)
			draw_line(p, p + Vector2(6,-8), Color(warning, .8), 1.2)
		var badge := Rect2(rect.position + Vector2(s-18, 2), Vector2(15,17))
		draw_rect(badge, Color("#783725"))
		_center_text(badge.get_center()+Vector2(0,4), "!", 13, Color("#fff2ce"))
	if flash_time > 0 and flash_cells.has(index) and not reduced_motion:
		draw_rect(rect, Color(1,.7,.25,flash_time * .6))

func _tree(center: Vector2, s: float, variant: float, burning: bool) -> void:
	draw_circle(center+Vector2(.06,.31)*s, s*.25, Color(0,0,0,.21))
	draw_rect(Rect2(center+Vector2(-.04,.02)*s, Vector2(.08,.36)*s), Color("#bd9365"))
	var sway: float = sin(time * .9 + variant * 6) * s * .012 if not reduced_motion else 0.0
	var tip: Vector2 = center + Vector2(sway,-.35*s)
	var foliage: Color = Color("#367f61").lightened(variant*.15)
	if burning:
		foliage = Color("#605532")
	var silhouette := PackedVector2Array([tip,center+Vector2(.3,.27)*s,center+Vector2(-.29,.27)*s])
	draw_colored_polygon(silhouette, foliage)
	draw_colored_polygon(PackedVector2Array([tip,center+Vector2(0,.27)*s,center+Vector2(-.29,.27)*s]), foliage.lightened(.17))
	draw_line(tip+Vector2(0,.18)*s,center+Vector2(.08,.25)*s,foliage.darkened(.18),1)
	draw_line(center+Vector2(-.14,.08)*s,center+Vector2(.18,.13)*s,foliage.lightened(.07),1)

func _house(center: Vector2, s: float) -> void:
	draw_circle(center+Vector2(.04,.22)*s, s*.32, Color(0,0,0,.2))
	draw_rect(Rect2(center+Vector2(-.27,-.03)*s,Vector2(.53,.36)*s),Color("#e7d5ad"))
	draw_rect(Rect2(center+Vector2(.09,-.03)*s,Vector2(.17,.36)*s),Color("#c2ad88"))
	draw_colored_polygon(PackedVector2Array([center+Vector2(-.35,-.02)*s,center+Vector2(-.03,-.32)*s,center+Vector2(.34,-.02)*s]),Color("#bd6950"))
	draw_line(center+Vector2(-.35,-.02)*s,center+Vector2(-.03,-.32)*s,Color("#ecae7e"),2)
	draw_rect(Rect2(center+Vector2(-.065,.1)*s,Vector2(.12,.23)*s),Color("#5c5a46"))
	draw_rect(Rect2(center+Vector2(-.2,.08)*s,Vector2(.09,.08)*s),Color("#ffdb88"))
	draw_rect(Rect2(center+Vector2(.125,.08)*s,Vector2(.09,.08)*s),Color("#ffdb88"))

func _fire(center: Vector2, s: float, phase: float) -> void:
	var flicker: float = sin(time*6.0 + phase)*.07 if not reduced_motion else 0.0
	var base: Vector2 = center + Vector2(0,.28)*s
	draw_circle(center,s*.42,Color(1,.37,.07,.12))
	draw_colored_polygon(PackedVector2Array([base+Vector2(-.29,0)*s,base+Vector2(-.24,-.3)*s,base+Vector2(-.09,-.49-flicker)*s,base+Vector2(0,-.29)*s,base+Vector2(.13,-.67+flicker)*s,base+Vector2(.31,-.19)*s,base+Vector2(.24,.01)*s]),Color("#f57c46"))
	draw_colored_polygon(PackedVector2Array([base+Vector2(-.16,0)*s,base+Vector2(-.11,-.27)*s,base+Vector2(.025,-.43-flicker)*s,base+Vector2(.19,-.08)*s,base+Vector2(.14,.02)*s]),Color("#f7be64"))
	draw_colored_polygon(PackedVector2Array([base+Vector2(-.06,0)*s,base+Vector2(0,-.2)*s,base+Vector2(.08,0)*s]),Color("#ffe9ad"))

func _center_text(pos: Vector2, text: String, font_size: int, color: Color) -> void:
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, pos-Vector2(width*.5,0), text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)
