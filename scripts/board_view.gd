class_name MyceliumBoard
extends Control
## Векторная отрисовка поля. Внешние изображения компонентов не требуются.

signal tile_clicked(coord: Vector3i)
signal tile_hovered(coord: Vector3i)

const Tri = preload("res://scripts/triangle_grid.gd")
const TILE_COLORS := {
	"red": Color("#824943"), "green": Color("#416b52"),
	"brown": Color("#715843"), "yellow": Color("#927a42"), "black": Color("#383d40")
}
const TILE_SYMBOLS := {"red": "●", "green": "▲", "brown": "■", "yellow": "◆", "black": "★"}

var game: MyceliumGame
var highlights: Array[Vector3i] = []
var ghosts: Array[Vector3i] = []
var selected := Tri.INVALID
var wind_tile := Tri.INVALID
var path: Array[Vector3i] = []
var tile_size := 76.0
var origin := Vector2.ZERO
var fitted := false
var hovered := Tri.INVALID
var font: Font

var _press_position := Vector2.ZERO
var _left_pressed := false
var _dragging := false
var _pan_button := false

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = ThemeDB.fallback_font
	resized.connect(_on_resized)

func set_game(value: MyceliumGame, refit: bool = false) -> void:
	game = value
	if refit:
		fitted = false
		fit_board()
	queue_redraw()

func clear_highlights() -> void:
	highlights.clear()
	ghosts.clear()
	path.clear()
	selected = Tri.INVALID
	wind_tile = Tri.INVALID
	queue_redraw()

func _on_resized() -> void:
	if not fitted:
		fit_board()
	queue_redraw()

func fit_board() -> void:
	if game == null or game.tiles.is_empty() or size.x < 10 or size.y < 10:
		return
	var bounds := Rect2(Vector2.ZERO, Vector2.ZERO)
	var first := true
	for coord in game.tiles:
		for vertex in Tri.polygon(coord, 1.0):
			if first:
				bounds = Rect2(vertex, Vector2.ZERO)
				first = false
			else:
				bounds = bounds.expand(vertex)
	if first:
		return
	tile_size = clampf(minf((size.x - 90.0) / maxf(bounds.size.x, 1.0), (size.y - 70.0) / maxf(bounds.size.y, 0.5)), 38.0, 132.0)
	origin = size * 0.5 - bounds.get_center() * tile_size
	fitted = true
	queue_redraw()

func _screen_point(world: Vector2) -> Vector2:
	return origin + world * tile_size

func _screen_polygon(coord: Vector3i) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in Tri.polygon(coord, 1.0):
		result.append(_screen_point(point))
	return result

func _screen_center(coord: Vector3i) -> Vector2:
	return _screen_point(Tri.center(coord, 1.0))

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#101b18"))
	_draw_background_grid()
	if game == null:
		return
	for coord in ghosts:
		if not game.tiles.has(coord):
			_draw_ghost(coord)
	for coord in game.tiles:
		_draw_tile(coord)
	if path.size() > 1:
		for i in range(1, path.size()):
			draw_line(_screen_center(path[i - 1]), _screen_center(path[i]), Color("#f4dd8b"), 4.0, true)
		for i in range(path.size()):
			var center := _screen_center(path[i])
			draw_circle(center, 10.0, Color("#f4dd8b"))
			_text(str(i), center + Vector2(0, 4), 11, Color("#24352c"), true)
	if game.phase == "finished":
		draw_rect(Rect2(Vector2(12, 12), Vector2(230, 34)), Color(0.05, 0.1, 0.08, 0.85), true)
		_text("ПАРТИЯ ЗАВЕРШЕНА", Vector2(24, 35), 15, Color("#f2d58a"))

func _draw_background_grid() -> void:
	var color := Color(0.5, 0.7, 0.6, 0.035)
	var spacing := 32.0
	for x in range(0, int(size.x) + 32, 32):
		draw_line(Vector2(x, 0), Vector2(x, size.y), color)
	for y in range(0, int(size.y) + 32, 32):
		draw_line(Vector2(0, y), Vector2(size.x, y), color)

func _draw_ghost(coord: Vector3i) -> void:
	var polygon := _screen_polygon(coord)
	var fill := Color(0.55, 0.85, 0.68, 0.075 if not coord in highlights else 0.2)
	draw_colored_polygon(polygon, fill)
	var closed := polygon.duplicate()
	closed.append(polygon[0])
	draw_polyline(closed, Color(0.6, 0.85, 0.7, 0.45), 1.5, true)
	var center := _screen_center(coord)
	_text("+", center + Vector2(0, 8), 24, Color("#b9d9bd"), true)

func _draw_tile(coord: Vector3i) -> void:
	var tile: Dictionary = game.tiles[coord]
	var polygon := _screen_polygon(coord)
	var center := _screen_center(coord)
	var base: Color = TILE_COLORS.get(tile["color"], Color.DARK_SLATE_GRAY)
	if coord == hovered:
		base = base.lightened(0.12)
	draw_colored_polygon(polygon, base)
	# Абстрактные гифы — нейтральная заглушка вместо оригинального арта.
	var inner := PackedVector2Array()
	for point in polygon:
		inner.append(center + (point - center) * 0.76)
	var inner_closed := inner.duplicate()
	inner_closed.append(inner[0])
	draw_polyline(inner_closed, Color(0.85, 0.9, 0.78, 0.14), 1.0, true)
	for point in polygon:
		draw_line(center, center + (point - center) * 0.72, Color(0.85, 0.9, 0.78, 0.09), 1.0, true)
	var border := Color(0.75, 0.82, 0.72, 0.36)
	var width := 1.3
	if coord in highlights:
		border = Color("#b9edc5")
		width = 3.2
	if coord == selected:
		border = Color("#f3d27e")
		width = 3.5
	var closed := polygon.duplicate()
	closed.append(polygon[0])
	draw_polyline(closed, border, width, true)
	var symbol: String = TILE_SYMBOLS.get(tile["color"], "?")
	_text(symbol, center + Vector2(-tile_size * 0.27, -tile_size * 0.11), maxi(10, int(tile_size * 0.15)), Color(0.95, 0.93, 0.82, 0.55), true)
	_draw_spores(coord, center)
	if tile["insect"]:
		_draw_insect(center + Vector2(0, tile_size * 0.24))
	if tile["mushroom"] != -1:
		_draw_mushroom(center + Vector2(-tile_size * 0.10, 2), int(tile["mushroom"]), int(tile["slot"]))
	var queen := game.queen_at(coord)
	if queen != -1:
		_draw_queen(center + Vector2(tile_size * 0.12, -tile_size * 0.07), queen)
	if coord == wind_tile:
		_draw_wind_labels(coord)

func _draw_spores(coord: Vector3i, center: Vector2) -> void:
	var tile: Dictionary = game.tiles[coord]
	var active_players: Array = []
	for player_id in range(game.players.size()):
		if int(tile["spores"][player_id]) > 0:
			active_players.append(player_id)
	if active_players.is_empty():
		return
	var group := 0
	for player_id in active_players:
		var count := int(tile["spores"][player_id])
		var side := -1.0 if group % 2 == 0 else 1.0
		var base := center + Vector2(side * tile_size * 0.19, tile_size * (0.10 + 0.09 * (group / 2)))
		for i in range(mini(count, 5)):
			var angle := float(i) * TAU / 5.0
			var radius := 5.0 if i > 0 else 0.0
			var dot := base + Vector2(cos(angle), sin(angle)) * radius
			draw_circle(dot, maxf(3.0, tile_size * 0.047), game.player_color(player_id))
			draw_arc(dot, maxf(3.0, tile_size * 0.047), 0, TAU, 12, Color(0.05, 0.1, 0.08, 0.65), 1.0, true)
		if count > 1:
			_text(str(count), base + Vector2(9, 4), 10, Color("#fff3d5"), true)
		group += 1

func _draw_insect(center: Vector2) -> void:
	var gold := Color("#e9c86e")
	var radius := maxf(6.0, tile_size * 0.085)
	draw_circle(center, radius, Color("#2d382c"))
	draw_arc(center, radius, 0, TAU, 20, gold, 1.4, true)
	draw_line(center + Vector2(0, -radius * 0.6), center + Vector2(0, radius * 0.6), gold, 2.0, true)
	for sign_value in [-1, 1]:
		draw_line(center + Vector2(0, -2), center + Vector2(sign_value * radius * 0.7, -radius * 0.6), gold, 1.3, true)
		draw_line(center + Vector2(0, 2), center + Vector2(sign_value * radius * 0.7, radius * 0.6), gold, 1.3, true)

func _draw_mushroom(center: Vector2, player_id: int, slot: int) -> void:
	var color: Color = game.player_color(player_id)
	var scale_factor := tile_size / 76.0
	var cap := PackedVector2Array([
		center + Vector2(-17, 0) * scale_factor, center + Vector2(-13, -10) * scale_factor,
		center + Vector2(0, -16) * scale_factor, center + Vector2(13, -10) * scale_factor,
		center + Vector2(17, 0) * scale_factor
	])
	draw_colored_polygon(cap, color)
	draw_polyline(cap, color.lightened(0.35), 1.2, true)
	draw_rect(Rect2(center + Vector2(-4, -1) * scale_factor, Vector2(8, 15) * scale_factor), Color("#e9dfc6"))
	_text(str(slot + 1), center + Vector2(0, 9) * scale_factor, maxi(9, int(10 * scale_factor)), Color("#26352e"), true)
	if game.is_mushroom_blocked(player_id, slot):
		_text("×", center + Vector2(17, -10) * scale_factor, maxi(14, int(20 * scale_factor)), Color("#ffd083"), true)

func _draw_queen(center: Vector2, player_id: int) -> void:
	var color: Color = game.player_color(player_id)
	var radius := maxf(10.0, tile_size * 0.15)
	draw_circle(center, radius + 2.0, Color(0.05, 0.09, 0.07, 0.75))
	draw_circle(center, radius, color)
	var crown := PackedVector2Array([
		center + Vector2(-9, -6), center + Vector2(-8, -16), center + Vector2(-2, -10),
		center + Vector2(3, -18), center + Vector2(7, -9), center + Vector2(12, -14), center + Vector2(9, -5)
	])
	draw_polyline(crown, Color("#fff0b8"), 2.0, true)
	_text("Ц", center + Vector2(0, 5), maxi(11, int(radius)), Color("#1b2922"), true)

func _draw_wind_labels(coord: Vector3i) -> void:
	var tile: Dictionary = game.tiles[coord]
	var edges := Tri.edges(coord)
	for edge_index in range(3):
		var edge: Array = edges[edge_index]
		var midpoint := (Tri.lattice_to_pixel(edge[0]) + Tri.lattice_to_pixel(edge[1])) * 0.5
		var center := Tri.center(coord)
		midpoint = midpoint.lerp(center, 0.18)
		var wind := posmod(edge_index - int(tile["rotation"]), 3)
		_text(Tri.WIND_NAMES[wind], _screen_point(midpoint) + Vector2(0, 4), maxi(11, int(tile_size * 0.16)), Color("#fff0b3"), true)

func _text(text: String, position: Vector2, font_size: int, color: Color, centered: bool = false) -> void:
	if font == null:
		return
	var pos := position
	if centered:
		pos.x -= font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * 0.5
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _coord_at(point: Vector2) -> Vector3i:
	if game == null:
		return Tri.INVALID
	# Сначала реальные тайлы, затем призрачные позиции разведки.
	for coord in game.tiles:
		if Geometry2D.is_point_in_polygon(point, _screen_polygon(coord)):
			return coord
	for coord in ghosts:
		if not game.tiles.has(coord) and Geometry2D.is_point_in_polygon(point, _screen_polygon(coord)):
			return coord
	return Tri.INVALID

func _update_hover(point: Vector2) -> void:
	var coord := _coord_at(point)
	if coord == hovered:
		return
	hovered = coord
	if game != null and game.tiles.has(coord):
		var tile: Dictionary = game.tiles[coord]
		var lines: Array[String] = [game.color_name(tile["color"])]
		var spore_parts: Array[String] = []
		for player_id in range(game.players.size()):
			var count := int(tile["spores"][player_id])
			if count > 0:
				spore_parts.append("%s: %d" % [game.players[player_id]["name"], count])
		if not spore_parts.is_empty(): lines.append("Споры — " + ", ".join(spore_parts))
		if tile["mushroom"] != -1:
			lines.append("Гриб: %s, планшет %d" % [game.players[tile["mushroom"]]["name"], int(tile["slot"]) + 1])
		var queen := game.queen_at(coord)
		if queen != -1: lines.append("Царица: " + game.players[queen]["name"])
		if tile["insect"]: lines.append("Жетон насекомого")
		lines.append(Tri.tile_to_string(coord))
		tooltip_text = "\n".join(lines)
		tile_hovered.emit(coord)
	else:
		tooltip_text = "Позиция для нового тайла" if coord != Tri.INVALID else ""
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			_zoom_at(button.position, 1.12)
			accept_event()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			_zoom_at(button.position, 1.0 / 1.12)
			accept_event()
		elif button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_left_pressed = true
				_press_position = button.position
				_dragging = false
			else:
				if _left_pressed and not _dragging:
					var coord := _coord_at(button.position)
					if coord != Tri.INVALID:
						tile_clicked.emit(coord)
				_left_pressed = false
				_dragging = false
			accept_event()
		elif button.button_index == MOUSE_BUTTON_RIGHT or button.button_index == MOUSE_BUTTON_MIDDLE:
			_pan_button = button.pressed
			accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _pan_button or (_left_pressed and motion.position.distance_to(_press_position) > 7.0):
			if _left_pressed: _dragging = true
			origin += motion.relative
			queue_redraw()
		else:
			_update_hover(motion.position)

func _zoom_at(point: Vector2, factor: float) -> void:
	var new_size := clampf(tile_size * factor, 30.0, 150.0)
	var world := (point - origin) / tile_size
	tile_size = new_size
	origin = point - world * tile_size
	fitted = true
	queue_redraw()
