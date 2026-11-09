class_name MyceliumCard
extends Button
## Карта-заглушка: вся информация берётся из JSON, иллюстрация векторная.

const COST_COLORS := {
	"red": Color("#b9574e"), "green": Color("#4f8c62"), "brown": Color("#806047"),
	"yellow": Color("#d3aa43"), "black": Color("#343a3b"), "any": Color("#e8e0c9")
}
const COST_SYMBOLS := {"red": "●", "green": "▲", "brown": "■", "yellow": "◆", "black": "★", "any": "?"}

var data: Dictionary = {}
var selected := false
var face_down := false
var compact := false
var font: Font

func _ready() -> void:
	font = ThemeDB.fallback_font
	text = ""
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(154, 212) if not compact else Vector2(142, 84)
	focus_mode = Control.FOCUS_NONE

func setup(definition: Dictionary, is_selected: bool = false, is_compact: bool = false) -> void:
	data = definition
	selected = is_selected
	compact = is_compact
	custom_minimum_size = Vector2(154, 212) if not compact else Vector2(142, 84)
	if not data.is_empty():
		tooltip_text = "%s\n%s\nОчки: %s · Споры: %s\nЦена: %s\n%s" % [
			data.get("name", "Карта"), data.get("latin", ""), _num(data.get("points", "—")),
			_num(data.get("spores", data.get("spores_medium", "—"))), ", ".join(data.get("cost", [])),
			data.get("effect_text", "Без эффекта")
		]
	queue_redraw()

func _draw() -> void:
	if font == null: font = ThemeDB.fallback_font
	var rect := Rect2(Vector2(2, 2), size - Vector2(4, 4))
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#eee6d2") if not face_down else Color("#294438")
	style.set_corner_radius_all(10)
	style.set_border_width_all(3 if selected else 1)
	style.border_color = Color("#d2edba") if selected else Color("#63776a")
	draw_style_box(style, rect)
	if face_down:
		_draw_back(rect)
		return
	if data.is_empty():
		_text("ПУСТО", Vector2(size.x * 0.5, size.y * 0.52), 14, Color("#657065"), true)
		return
	if compact:
		_draw_compact(rect)
		return
	# Верхняя строка и очки.
	if bool(data.get("placeholder", false)):
		var badge := Rect2(10, 9, 43, 17)
		draw_rect(badge, Color("#c9b789"), true)
		_text("ДЕМО", Vector2(31, 22), 10, Color("#344139"), true)
	var diamond := PackedVector2Array([
		Vector2(size.x - 26, 8), Vector2(size.x - 9, 26), Vector2(size.x - 26, 44), Vector2(size.x - 43, 26)
	])
	draw_colored_polygon(diamond, Color("#e4b94f"))
	_text(_num(data.get("points", "—")), Vector2(size.x - 26, 32), 18, Color("#3e3a2c"), true)
	_draw_mushroom(Vector2(size.x * 0.50, 70), 0.9)
	var name_lines := _wrap(str(data.get("name", "Карта")), 20, 2)
	var y := 112.0
	for line in name_lines:
		_text(line, Vector2(size.x * 0.5, y), 14, Color("#29362f"), true)
		y += 16
	_text(str(data.get("latin", "")), Vector2(size.x * 0.5, y + 1), 9, Color("#788078"), true)
	# Ресурсы и число спор.
	var costs: Array = data.get("cost", [])
	var start_x := 17.0
	for i in range(costs.size()):
		var center := Vector2(start_x + i * 20, 154)
		var color_id := str(costs[i])
		draw_circle(center, 8, COST_COLORS.get(color_id, Color.GRAY))
		_text(COST_SYMBOLS.get(color_id, "?"), center + Vector2(0, 4), 9, Color("#fff4dc") if color_id != "any" else Color("#3a4139"), true)
	_text("Споры: %s" % _num(data.get("spores", data.get("spores_medium", "—"))), Vector2(size.x - 12, 159), 11, Color("#3f5145"), false, true)
	var effect_type := str(data.get("effect_type", "instant"))
	var band_color := Color("#c7b4cf") if effect_type == "persistent" else Color("#d2b09a") if effect_type == "mushroom" else Color("#dcc990")
	draw_rect(Rect2(7, 169, size.x - 14, size.y - 176), band_color, true)
	var lines := _wrap(str(data.get("effect_text", "Без эффекта")), 27, 3)
	var effect_y := 183.0
	for line in lines:
		_text(line, Vector2(12, effect_y), 9, Color("#3d4038"))
		effect_y += 11

func _draw_compact(rect: Rect2) -> void:
	draw_rect(Rect2(8, 9, 5, rect.size.y - 18), Color("#b69a55"), true)
	_text(str(data.get("name", "Карта")), Vector2(20, 25), 12, Color("#29362f"))
	_text("Очки %s · Споры %s" % [_num(data.get("points", "5")), _num(data.get("spores", data.get("spores_medium", "—")))], Vector2(20, 45), 10, Color("#56655a"))
	_text(str(data.get("effect_text", "")), Vector2(20, 65), 8, Color("#6c6d60"))

func _draw_back(rect: Rect2) -> void:
	var center := rect.get_center()
	for radius in [25.0, 40.0, 55.0]:
		draw_arc(center, radius, 0, TAU, 48, Color(0.7, 0.83, 0.68, 0.2), 1.2, true)
	for i in range(8):
		var angle := float(i) * TAU / 8.0
		draw_line(center + Vector2(cos(angle), sin(angle)) * 15, center + Vector2(cos(angle), sin(angle)) * 60, Color(0.7, 0.83, 0.68, 0.16), 1.0, true)
	_text("МИЦЕЛИЙ", center + Vector2(0, 5), 13, Color("#c1d0b9"), true)

func _draw_mushroom(center: Vector2, scale_factor: float) -> void:
	var cap := PackedVector2Array([
		center + Vector2(-31, 0) * scale_factor, center + Vector2(-24, -18) * scale_factor,
		center + Vector2(0, -29) * scale_factor, center + Vector2(24, -18) * scale_factor,
		center + Vector2(31, 0) * scale_factor
	])
	draw_colored_polygon(cap, Color("#9c5e4e"))
	draw_polyline(cap, Color("#6d493e"), 1.4, true)
	draw_rect(Rect2(center + Vector2(-7, -1) * scale_factor, Vector2(14, 28) * scale_factor), Color("#d9c7a6"))
	for offset in [-13, 0, 13]:
		draw_circle(center + Vector2(offset, -12 - abs(offset) * 0.25) * scale_factor, 2.4 * scale_factor, Color("#e7d5b5"))

func _num(value: Variant) -> String:
	if value is float or value is int:
		return str(int(value)) if is_equal_approx(float(value), roundf(float(value))) else str(value)
	return str(value)

func _wrap(value: String, max_chars: int, max_lines: int) -> Array[String]:
	var result: Array[String] = []
	var words := value.split(" ")
	var line := ""
	for word in words:
		if (line + " " + word).strip_edges().length() > max_chars and not line.is_empty():
			result.append(line)
			line = str(word)
			if result.size() >= max_lines: break
		else:
			line = (line + " " + word).strip_edges()
	if result.size() < max_lines and not line.is_empty(): result.append(line)
	if result.size() == max_lines and result[max_lines - 1].length() >= max_chars:
		result[max_lines - 1] = result[max_lines - 1].left(max_chars - 1) + "…"
	return result

func _text(value: String, position: Vector2, font_size: int, color: Color, centered: bool = false, right: bool = false) -> void:
	var pos := position
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if centered: pos.x -= width * 0.5
	if right: pos.x -= width
	draw_string(font, pos, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
