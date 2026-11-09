class_name TriGrid
extends RefCounted
## Геометрия регулярной треугольной решётки.
## Тайл Vector3i(x, y, orientation), orientation: 0 = вершиной вниз, 1 = вверх.
## Координаты вершин целочисленные, поэтому соседство не зависит от погрешностей float.

const INVALID := Vector3i(-32767, -32767, -32767)
const HEIGHT := sqrt(3.0) / 2.0
const WIND_NAMES := ["O", "U", "A"]

static func vertices(tile: Vector3i) -> Array[Vector2i]:
	var x := tile.x
	var y := tile.y
	if tile.z == 0:
		return [Vector2i(x, y), Vector2i(x + 1, y), Vector2i(x, y + 1)]
	return [Vector2i(x + 1, y), Vector2i(x, y + 1), Vector2i(x + 1, y + 1)]

static func lattice_to_pixel(vertex: Vector2i, size: float = 1.0) -> Vector2:
	return Vector2((float(vertex.x) + float(vertex.y) * 0.5) * size, float(vertex.y) * HEIGHT * size)

static func center(tile: Vector3i, size: float = 1.0) -> Vector2:
	var result := Vector2.ZERO
	for vertex in vertices(tile):
		result += lattice_to_pixel(vertex, size)
	return result / 3.0

static func polygon(tile: Vector3i, size: float = 1.0) -> PackedVector2Array:
	var result := PackedVector2Array()
	for vertex in vertices(tile):
		result.append(lattice_to_pixel(vertex, size))
	return result

static func edges(tile: Vector3i) -> Array:
	var v := vertices(tile)
	return [[v[0], v[1]], [v[1], v[2]], [v[2], v[0]]]

static func shared_vertices(a: Vector3i, b: Vector3i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var bv := vertices(b)
	for vertex in vertices(a):
		if vertex in bv:
			result.append(vertex)
	return result

static func adjacent(a: Vector3i, b: Vector3i) -> bool:
	return a != b and shared_vertices(a, b).size() == 2

static func candidates(tile: Vector3i) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for orientation in range(2):
				var other := Vector3i(tile.x + dx, tile.y + dy, orientation)
				if adjacent(tile, other):
					result.append(other)
	return result

static func neighbors(tile: Vector3i, board: Dictionary) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for other in candidates(tile):
		if board.has(other):
			result.append(other)
	return result

static func frontier(board: Dictionary) -> Array[Vector3i]:
	var seen := {}
	var result: Array[Vector3i] = []
	for tile in board:
		for other in candidates(tile):
			if not board.has(other) and not seen.has(other):
				seen[other] = true
				result.append(other)
	result.sort_custom(func(a: Vector3i, b: Vector3i):
		var ca := center(a)
		var cb := center(b)
		return ca.y < cb.y if not is_equal_approx(ca.y, cb.y) else ca.x < cb.x
	)
	return result

static func _sort_radial(tiles: Array[Vector3i]) -> void:
	tiles.sort_custom(func(a: Vector3i, b: Vector3i):
		var ca := center(a)
		var cb := center(b)
		return atan2(ca.y, ca.x) < atan2(cb.y, cb.x)
	)

static func star_setup() -> Dictionary:
	# Шесть треугольников вокруг одной вершины образуют центральный шестиугольник.
	var central: Array[Vector3i] = []
	var origin := Vector2i.ZERO
	for x in range(-1, 1):
		for y in range(-1, 1):
			for orientation in range(2):
				var tile := Vector3i(x, y, orientation)
				if origin in vertices(tile):
					central.append(tile)
	_sort_radial(central)
	var central_lookup := {}
	for tile in central:
		central_lookup[tile] = true
	var outer: Array[Vector3i] = []
	for tile in central:
		for edge in edges(tile):
			if origin in edge:
				continue
			for other in candidates(tile):
				if central_lookup.has(other):
					continue
				var ov := vertices(other)
				if edge[0] in ov and edge[1] in ov:
					outer.append(other)
					break
	var all_tiles: Array[Vector3i] = []
	# Чередование центра и лучей даёт наглядный порядок раздачи из двух стопок.
	for i in range(central.size()):
		all_tiles.append(central[i])
		if i < outer.size():
			all_tiles.append(outer[i])
	return {"central": central, "outer": outer, "all": all_tiles}

static func edge_for_wind(tile: Vector3i, rotation: int, wind: int) -> int:
	return posmod(wind + rotation, 3)

static func _cross(a: Vector2i, b: Vector2i, point: Vector2) -> float:
	# a/b заданы в координатах решётки, а point — в экранной геометрии.
	# Переводим обе вершины, иначе проверка полуплоскостей не симметрична.
	var pa := lattice_to_pixel(a)
	var pb := lattice_to_pixel(b)
	return (pb - pa).cross(point - pa)

static func _inside_dispersal_wedge(source: Vector3i, tile: Vector3i, edge_index: int) -> bool:
	if tile == source:
		return true
	var source_edges := edges(source)
	var source_center := center(source)
	var tile_center := center(tile)
	for i in range(3):
		if i == edge_index:
			continue
		var edge: Array = source_edges[i]
		var source_sign := _cross(edge[0], edge[1], source_center)
		var tile_sign := _cross(edge[0], edge[1], tile_center)
		if source_sign * tile_sign < -0.00001:
			return false
	return true

static func dispersal_layers(board: Dictionary, source: Vector3i, rotation: int, wind: int) -> Array:
	## Слой 0 — источник, слой 1 — тайл за выбранной стороной.
	## Далее BFS только внутри угла, образованного продолжением двух других сторон.
	## Каждый следующий слой можно заполнять после предыдущего; выбор внутри слоя свободен.
	var layers: Array = [[source]]
	if not board.has(source):
		return layers
	var edge_index := edge_for_wind(source, rotation, wind)
	var visited := {source: true}
	var depth := {source: 0}
	var queue: Array[Vector3i] = [source]
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		for other in candidates(current):
			if not board.has(other) or visited.has(other):
				continue
			if current == source:
				# Первая спора после источника идёт строго через сторону ветра,
				# даже если сосед через другую сторону касается границы угла.
				var selected_edge: Array = edges(source)[edge_index]
				var common := shared_vertices(source, other)
				if not (selected_edge[0] in common and selected_edge[1] in common):
					continue
			if not _inside_dispersal_wedge(source, other, edge_index):
				continue
			visited[other] = true
			depth[other] = depth[current] + 1
			var d: int = depth[other]
			while layers.size() <= d:
				layers.append([])
			layers[d].append(other)
			queue.append(other)
	for layer in layers:
		layer.sort_custom(func(a: Vector3i, b: Vector3i):
			var ca := center(a)
			var cb := center(b)
			return ca.x < cb.x if not is_equal_approx(ca.y, cb.y) else ca.y < cb.y
		)
	return layers

static func tile_to_string(tile: Vector3i) -> String:
	return "%d,%d,%d" % [tile.x, tile.y, tile.z]

static func tile_from_string(value: String) -> Vector3i:
	var parts := value.split(",")
	if parts.size() != 3:
		return INVALID
	return Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))

static func distance_path(board: Dictionary, start: Vector3i, goal: Vector3i, blocked: Dictionary = {}) -> Array[Vector3i]:
	var empty: Array[Vector3i] = []
	if not board.has(start) or not board.has(goal):
		return empty
	if start == goal:
		return [start]
	var queue: Array[Vector3i] = [start]
	var previous := {start: start}
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		for other in neighbors(current, board):
			if previous.has(other) or (blocked.has(other) and other != goal):
				continue
			previous[other] = current
			if other == goal:
				var path: Array[Vector3i] = [goal]
				var step := goal
				while step != start:
					step = previous[step]
					path.push_front(step)
				return path
			queue.append(other)
	return empty
