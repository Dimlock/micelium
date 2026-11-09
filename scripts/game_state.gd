class_name MyceliumGame
extends RefCounted
## Правила и состояние партии. UI не хранит игровую логику.
## Все ID карт/тайлов и их характеристики приходят из data/components.json.

signal changed
signal notified(text: String)

const Tri = preload("res://scripts/triangle_grid.gd")
const COMPONENTS_PATH := "res://data/components.json"
const PLAYER_HEX := ["#e56b5d", "#62a8e5", "#e7bd51", "#a47bd8", "#75c997"]
const ACTIONS := ["move", "explore", "disperse", "grow", "decompose", "develop"]
const ACTION_NAMES := {
	"move": "Перемещение", "explore": "Разведка", "disperse": "Развеивание",
	"grow": "Выращивание", "decompose": "Разложение", "develop": "Развитие"
}

var components: Dictionary = {}
var cards: Dictionary = {}
var tile_defs: Dictionary = {}
var automa_cards: Dictionary = {}
var rng := RandomNumberGenerator.new()

var players: Array = []
var tiles: Dictionary = {}
var tile_stacks: Array = [[], []]
var central_tiles: Array[Vector3i] = []
var deck: Array = []
var market: Array = []
var automa_deck: Array = []
var automa_discard: Array = []
var automa_current_card := ""
var automa_difficulty := "medium"
var human_count := 2
var board_count := 5
var insect_supply := 20
var current_player := 0
var first_player := 0
var phase := "menu" # queens / playing / finished
var actions_left := 0
var actions_used: Array = []
var setup_order: Array = []
var setup_cursor := 0
var turn_number := 1
var end_token_owner := -1
var game_log: Array[String] = []
var dispersal: Dictionary = {}
var pending_development: Dictionary = {}

var _payment_resources: Array = []
var _payment_cost_order: Array = []
var _payment_used: Dictionary = {}
var _payment_solution: Array = []

func _init() -> void:
	load_components()

func load_components() -> void:
	var file := FileAccess.open(COMPONENTS_PATH, FileAccess.READ)
	if file == null:
		push_error("Не найден файл компонентов: " + COMPONENTS_PATH)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Некорректный JSON компонентов")
		return
	components = parsed
	cards.clear()
	tile_defs.clear()
	automa_cards.clear()
	for definition in components.get("cards", []):
		cards[definition["id"]] = definition
	for definition in components.get("tiles", []):
		tile_defs[definition["id"]] = definition
	for definition in components.get("automa", []):
		automa_cards[definition["id"]] = definition

func is_placeholder_set() -> bool:
	return bool(components.get("meta", {}).get("is_placeholder", true))

func player_color(player_id: int) -> Color:
	return Color(PLAYER_HEX[player_id % PLAYER_HEX.size()])

func current() -> Dictionary:
	if players.is_empty():
		return {}
	return players[current_player]

func card(card_id: String) -> Dictionary:
	return cards.get(card_id, {})

func automa_card(card_id: String) -> Dictionary:
	return automa_cards.get(card_id, {})

func _shuffle(array: Array) -> void:
	for i in range(array.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var temporary = array[i]
		array[i] = array[j]
		array[j] = temporary

func _new_slots() -> Array:
	var result: Array = []
	for i in range(board_count):
		result.append({"active": "", "decomposed": [], "dispersals": 0})
	return result

func new_game(humans: int = 2, boards: int = 5, with_automa: bool = false, seed_text: String = "", difficulty: String = "medium") -> void:
	load_components()
	human_count = clampi(humans, 1, 4)
	board_count = clampi(boards, 3, 5)
	automa_difficulty = difficulty
	if seed_text.strip_edges().is_empty():
		rng.randomize()
	elif seed_text.is_valid_int():
		rng.seed = int(seed_text)
	else:
		rng.seed = abs(seed_text.hash())
	players.clear()
	tiles.clear()
	deck.clear()
	market.clear()
	automa_deck.clear()
	automa_discard.clear()
	automa_current_card = ""
	game_log.clear()
	actions_used.clear()
	dispersal.clear()
	pending_development.clear()
	end_token_owner = -1
	turn_number = 1
	var total := human_count + (1 if with_automa and human_count < 4 else 0)
	for i in range(total):
		var is_automa := with_automa and i == total - 1
		players.append({
			"id": i, "name": "Автома" if is_automa else "Игрок %d" % (i + 1),
			"is_automa": is_automa, "insects": 0, "hand": [], "grown": [],
			"slots": _new_slots(), "queen": Tri.INVALID
		})
	insect_supply = 20
	for player in players:
		var starting: int = 2 if player["is_automa"] else 1
		player["insects"] = mini(starting, insect_supply)
		insect_supply -= player["insects"]
	_prepare_tile_stacks()
	_prepare_initial_board()
	for card_id in cards:
		deck.append(card_id)
	_shuffle(deck)
	for player in players:
		if not player["is_automa"]:
			for i in range(3):
				_draw_to_hand(player["id"])
	# Правило дополнительной карты только для обычной партии вдвоём.
	if human_count == 2 and total == 2:
		_draw_to_hand(1)
	for i in range(3):
		market.append(_draw_deck())
	for card_id in automa_cards:
		automa_deck.append(card_id)
	_shuffle(automa_deck)
	first_player = 0
	setup_order.clear()
	for i in range(human_count - 1, -1, -1):
		setup_order.append(i)
	if total > human_count:
		setup_order.append(total - 1) # Автома всегда размещает царицу последней.
	setup_cursor = 0
	current_player = setup_order[0]
	actions_left = 0
	phase = "queens"
	_log("Подготовка: разместите цариц в обратном порядке. Набор компонентов — демонстрационный.")
	changed.emit()

func _prepare_tile_stacks() -> void:
	var ids: Array = []
	var solo: bool = human_count == 1 and players.size() == 2 and players[1]["is_automa"]
	for tile_id in tile_defs:
		if solo and tile_defs[tile_id]["color"] == "black":
			continue
		ids.append(tile_id)
	_shuffle(ids)
	tile_stacks = [[], []]
	for i in range(ids.size()):
		tile_stacks[i % 2].append(ids[i])

func _prepare_initial_board() -> void:
	# Пересобираем звезду, если в её центре не хватает нечёрных тайлов для цариц.
	for attempt in range(30):
		tiles.clear()
		central_tiles.clear()
		var stacks: Array = [tile_stacks[0].duplicate(), tile_stacks[1].duplicate()]
		var shape := Tri.star_setup()
		var positions: Array = shape["all"]
		for i in range(positions.size()):
			var stack_index := i % 2
			if stacks[stack_index].is_empty():
				continue
			var tile_id: String = stacks[stack_index].pop_front()
			_add_tile(positions[i], tile_id, false)
		central_tiles.assign(shape["central"])
		var available := 0
		for coord in central_tiles:
			if tiles.has(coord) and tiles[coord]["color"] != "black":
				available += 1
		if available >= players.size():
			tile_stacks = stacks
			return
		_prepare_tile_stacks()
	push_warning("Не удалось пересобрать центр без чёрных тайлов; используется последний вариант")

func _add_tile(coord: Vector3i, tile_id: String, from_exploration: bool = true) -> void:
	var definition: Dictionary = tile_defs.get(tile_id, {})
	var spores: Array = []
	for i in range(players.size()):
		spores.append(0)
	var insect := bool(definition.get("insect", false)) and insect_supply > 0
	if insect:
		insect_supply -= 1
	tiles[coord] = {
		"id": tile_id, "color": definition.get("color", "black"),
		"rotation": int(definition.get("rotation", 0)), "insect": insect,
		"spores": spores, "mushroom": -1, "slot": -1,
		"placeholder": bool(definition.get("placeholder", true))
	}
	if from_exploration:
		_log("%s добавляет тайл: %s%s" % [current().get("name", "?"), color_name(tiles[coord]["color"]), " + насекомое" if insect else ""])

func color_name(color_id: String) -> String:
	return str(components.get("colors", {}).get(color_id, color_id))

func initial_queen_choices(player_id: int = -1) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for coord in central_tiles:
		if not tiles.has(coord) or tiles[coord]["color"] == "black":
			continue
		if queen_at(coord) == -1:
			result.append(coord)
	return result

func place_initial_queen(coord: Vector3i) -> bool:
	if phase != "queens" or not coord in initial_queen_choices(current_player):
		return false
	players[current_player]["queen"] = coord
	_collect_insect(coord, current_player)
	_log("%s размещает царицу." % current()["name"])
	setup_cursor += 1
	if setup_cursor >= setup_order.size():
		phase = "playing"
		current_player = first_player
		actions_left = 2
		actions_used.clear()
		_log("Рынок открыт. Ход: %s." % current()["name"])
	else:
		current_player = setup_order[setup_cursor]
	changed.emit()
	return true

func choose_automa_initial_queen() -> Vector3i:
	var best := Tri.INVALID
	var best_score := -1000000.0
	for coord in initial_queen_choices(current_player):
		var score := 0.0
		for player in players:
			if player["id"] == current_player or player["queen"] == Tri.INVALID:
				continue
			var path := Tri.distance_path(tiles, coord, player["queen"])
			var distance: float = float(path.size()) if not path.is_empty() else 20.0
			score += minf(distance, 8.0)
		score += rng.randf() * 0.01
		if score > best_score:
			best_score = score
			best = coord
	return best

func queen_at(coord: Vector3i, except_player: int = -1) -> int:
	for player in players:
		if player["id"] != except_player and player["queen"] == coord:
			return player["id"]
	return -1

func find_mushroom(player_id: int, slot: int) -> Vector3i:
	for coord in tiles:
		if tiles[coord]["mushroom"] == player_id and tiles[coord]["slot"] == slot:
			return coord
	return Tri.INVALID

func is_mushroom_blocked(player_id: int, slot: int) -> bool:
	var coord := find_mushroom(player_id, slot)
	if coord == Tri.INVALID:
		return false
	var queen := queen_at(coord)
	return queen != -1 and queen != player_id

func _controller(coord: Vector3i) -> int:
	# Царица контролирует тайл даже поверх чужого гриба; такой гриб заблокирован.
	var queen := queen_at(coord)
	if queen != -1:
		return queen
	if tiles.has(coord):
		return int(tiles[coord]["mushroom"])
	return -1

func _collect_insect(coord: Vector3i, player_id: int) -> void:
	if tiles.has(coord) and tiles[coord]["insect"]:
		tiles[coord]["insect"] = false
		players[player_id]["insects"] += 1
		_log("%s получает жетон насекомого." % players[player_id]["name"])

func can_use_action(action: String, player_id: int = -1) -> bool:
	var p := current_player if player_id == -1 else player_id
	if phase != "playing" or p != current_player or actions_left <= 0:
		return false
	if action in actions_used and not has_bonus("repeat_action", p):
		return false
	return action in ACTIONS

func has_bonus(effect_id: String, player_id: int = -1, slot: int = -1) -> bool:
	var p := current_player if player_id == -1 else player_id
	if p < 0 or p >= players.size():
		return false
	var slots: Array = players[p]["slots"]
	var indices: Array = range(slots.size()) if slot == -1 else [slot]
	for index in indices:
		if index < 0 or index >= slots.size():
			continue
		for card_id in slots[index]["decomposed"]:
			var definition := card(card_id) if not players[p]["is_automa"] else automa_card(card_id)
			if definition.is_empty():
				# Разложенные карты автомы хранятся как ID карт автомы.
				definition = automa_card(card_id)
			if definition.get("effect_id", "") == effect_id:
				return true
	return false

func _consume_action(action: String) -> void:
	actions_used.append(action)
	actions_left = maxi(0, actions_left - 1)
	_log("%s: %s. Осталось действий: %d." % [current()["name"], ACTION_NAMES[action], actions_left])

func max_move_steps(player_id: int = -1) -> int:
	return 3 if has_bonus("queen_move_3", player_id) else 2

func valid_move_path(path: Array, player_id: int = -1) -> bool:
	var p := current_player if player_id == -1 else player_id
	if path.is_empty() or path.size() > max_move_steps(p):
		return false
	var position: Vector3i = players[p]["queen"]
	for coord in path:
		if not coord is Vector3i or not tiles.has(coord):
			return false
		if not Tri.adjacent(position, coord) or queen_at(coord, p) != -1:
			return false
		position = coord
	return true

func perform_move(path: Array) -> bool:
	if not can_use_action("move") or not valid_move_path(path):
		return false
	for coord in path:
		players[current_player]["queen"] = coord
		_collect_insect(coord, current_player)
	_consume_action("move")
	changed.emit()
	return true

func exploration_choices() -> Array[Vector3i]:
	return Tri.frontier(tiles)

func perform_explore(stack_index: int, coord: Vector3i) -> bool:
	if not can_use_action("explore") or stack_index < 0 or stack_index > 1:
		return false
	if tile_stacks[stack_index].is_empty() or not coord in exploration_choices():
		return false
	var tile_id: String = tile_stacks[stack_index].pop_front()
	_add_tile(coord, tile_id)
	_consume_action("explore")
	changed.emit()
	return true

func _draw_deck() -> String:
	if deck.is_empty():
		return ""
	return str(deck.pop_front())

func _draw_to_hand(player_id: int) -> String:
	var card_id := _draw_deck()
	if not card_id.is_empty() and not players[player_id]["is_automa"]:
		players[player_id]["hand"].append(card_id)
	return card_id

func _refill_market() -> void:
	for i in range(market.size()):
		if str(market[i]).is_empty():
			market[i] = _draw_deck()

func perform_develop_market(index: int) -> bool:
	if not can_use_action("develop") or index < 0 or index >= market.size():
		return false
	var card_id := str(market[index])
	if card_id.is_empty() or current()["is_automa"]:
		return false
	current()["hand"].append(card_id)
	market[index] = "" # Рынок пополняется после окончания хода.
	_log("%s берёт карту с рынка." % current()["name"])
	_consume_action("develop")
	changed.emit()
	return true

func perform_develop_deck() -> bool:
	if not can_use_action("develop") or deck.is_empty() or current()["is_automa"]:
		return false
	if has_bonus("development_draw_two_choose"):
		pending_development = {"cards": []}
		for i in range(mini(2, deck.size())):
			pending_development["cards"].append(_draw_deck())
		_log("Выберите одну из двух карт; другая уйдёт под низ колоды.")
	else:
		var card_id := _draw_to_hand(current_player)
		if card_id.is_empty():
			return false
		_log("%s берёт верхнюю карту колоды." % current()["name"])
		_consume_action("develop")
	changed.emit()
	return true

func choose_development(card_id: String) -> bool:
	if pending_development.is_empty() or not card_id in pending_development.get("cards", []):
		return false
	for drawn in pending_development["cards"]:
		if drawn == card_id:
			current()["hand"].append(drawn)
		else:
			deck.append(drawn)
	pending_development.clear()
	_consume_action("develop")
	changed.emit()
	return true

func perform_develop(source: String, market_index: int = -1) -> bool:
	return perform_develop_deck() if source == "deck" else perform_develop_market(market_index)

func get_mycelium(player_id: int) -> Array:
	## Тайл с активной чужой фишкой не связывает вашу грибницу.
	## На своём активном тайле доступны все споры; на нейтральном — только свои.
	var nodes := {}
	for coord in tiles:
		var controller := _controller(coord)
		if controller == player_id:
			nodes[coord] = true
		elif controller == -1 and tiles[coord]["spores"][player_id] > 0:
			nodes[coord] = true
	var unseen: Dictionary = nodes.duplicate()
	var result: Array = []
	while not unseen.is_empty():
		var start: Vector3i = unseen.keys()[0]
		var queue: Array[Vector3i] = [start]
		var component_nodes: Array[Vector3i] = []
		unseen.erase(start)
		var cursor := 0
		while cursor < queue.size():
			var coord := queue[cursor]
			cursor += 1
			component_nodes.append(coord)
			for other in Tri.neighbors(coord, tiles):
				if unseen.has(other):
					unseen.erase(other)
					queue.append(other)
		var resources: Array = []
		for coord in component_nodes:
			var controller := _controller(coord)
			for owner in range(players.size()):
				if controller != -1 and controller != player_id:
					continue
				if controller == -1 and owner != player_id:
					continue
				for count in range(tiles[coord]["spores"][owner]):
					resources.append({"coord": coord, "owner": owner, "color": tiles[coord]["color"]})
		result.append({"nodes": component_nodes, "resources": resources})
	return result

func _resource_matches(resource: Dictionary, required: String) -> bool:
	return required == "any" or resource["color"] == required or resource["color"] == "black"

func _payment_search(depth: int) -> bool:
	if depth >= _payment_cost_order.size():
		return true
	var required: String = _payment_cost_order[depth]
	# Сначала точные совпадения, чёрные универсальные тайлы берегём напоследок.
	for pass_index in range(2):
		for i in range(_payment_resources.size()):
			if _payment_used.has(i):
				continue
			var resource: Dictionary = _payment_resources[i]
			if not _resource_matches(resource, required):
				continue
			var is_wild: bool = resource["color"] == "black" and required != "any"
			if (pass_index == 0 and is_wild) or (pass_index == 1 and not is_wild and required != "any"):
				continue
			_payment_used[i] = true
			_payment_solution.append(resource)
			if _payment_search(depth + 1):
				return true
			_payment_solution.pop_back()
			_payment_used.erase(i)
	return false

func find_payment(resources: Array, costs: Array) -> Array:
	_payment_resources = resources
	_payment_cost_order = costs.duplicate()
	_payment_cost_order.sort_custom(func(a: String, b: String):
		if a == "any": return false
		if b == "any": return true
		return a < b
	)
	_payment_used.clear()
	_payment_solution.clear()
	if _payment_search(0):
		return _payment_solution.duplicate()
	return []

func find_payment_for_target(resources: Array, costs: Array, target: Vector3i) -> Array:
	## Недостаточно найти любую оплату: хотя бы одна потраченная спора обязана
	## находиться на свободном тайле, куда затем встанет новый гриб.
	## Перебираем назначение одной споры цели, остаток решаем обычным backtracking.
	for resource_index in range(resources.size()):
		var selected: Dictionary = resources[resource_index]
		if selected["coord"] != target:
			continue
		for cost_index in range(costs.size()):
			if not _resource_matches(selected, str(costs[cost_index])):
				continue
			var remaining_resources: Array = resources.duplicate()
			remaining_resources.remove_at(resource_index)
			var remaining_costs: Array = costs.duplicate()
			remaining_costs.remove_at(cost_index)
			var rest := find_payment(remaining_resources, remaining_costs)
			if rest.size() == remaining_costs.size():
				var result: Array = [selected]
				result.append_array(rest)
				return result
	return []

func find_growth_options(card_id: String, player_id: int = -1) -> Array:
	var p := current_player if player_id == -1 else player_id
	var result: Array = []
	if p < 0 or p >= players.size():
		return result
	var definition := automa_card(card_id) if players[p]["is_automa"] else card(card_id)
	if definition.is_empty():
		return result
	var free_slots: Array[int] = []
	for i in range(board_count):
		var slot: Dictionary = players[p]["slots"][i]
		if slot["active"].is_empty() and (not players[p]["is_automa"] or slot["decomposed"].is_empty()):
			free_slots.append(i)
	if free_slots.is_empty():
		return result
	var costs: Array = definition.get("cost", [])
	var networks := get_mycelium(p)
	for free_slot in free_slots:
		for network in networks:
			var free_targets: Array[Vector3i] = []
			for coord in network["nodes"]:
				if tiles[coord]["mushroom"] == -1:
					free_targets.append(coord)
			var payment: Array = []
			# Цель включается в оплату заранее; иначе первая найденная комбинация
			# могла ошибочно блокировать рост, хотя существовала другая легальная.
			for target in free_targets:
				payment = find_payment_for_target(network["resources"], costs, target)
				if payment.size() == costs.size():
					break
			if payment.size() != costs.size():
				continue
			var spent_tiles := {}
			for resource in payment:
				spent_tiles[resource["coord"]] = true
			var targets: Array[Vector3i] = []
			for coord in spent_tiles:
				if tiles[coord]["mushroom"] == -1:
					targets.append(coord)
			if not targets.is_empty():
				result.append({"payment": payment, "targets": targets, "slot": free_slot, "nodes": network["nodes"]})
	return result

func _same_payment(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	var left: Array = []
	for item in a:
		left.append(Tri.tile_to_string(item["coord"]) + ":" + str(item["owner"]))
	for item in b:
		var key := Tri.tile_to_string(item["coord"]) + ":" + str(item["owner"])
		if not key in left:
			return false
		left.erase(key)
	return left.is_empty()

func perform_growth(card_id: String, payment: Array, target: Vector3i, slot_choice: int = -1) -> bool:
	if not can_use_action("grow") or not tiles.has(target):
		return false
	if not current()["is_automa"] and not card_id in current()["hand"]:
		return false
	if current()["is_automa"] and card_id != automa_current_card:
		return false
	var valid_option: Dictionary = {}
	for option in find_growth_options(card_id):
		if slot_choice >= 0 and int(option["slot"]) != slot_choice:
			continue
		if target in option["targets"] and _same_payment(payment, option["payment"]):
			valid_option = option
			break
	if valid_option.is_empty():
		return false
	for resource in payment:
		tiles[resource["coord"]]["spores"][resource["owner"]] -= 1
	if not current()["is_automa"]:
		current()["hand"].erase(card_id)
	var slot: int = valid_option["slot"]
	current()["slots"][slot]["active"] = card_id
	current()["slots"][slot]["dispersals"] = 0
	current()["grown"].append(card_id)
	tiles[target]["mushroom"] = current_player
	tiles[target]["slot"] = slot
	_log("%s выращивает «%s» на планшете %d." % [current()["name"], definition_name(card_id, current()["is_automa"]), slot + 1])
	_consume_action("grow")
	changed.emit()
	return true

func definition_name(card_id: String, is_automa: bool = false) -> String:
	var definition := automa_card(card_id) if is_automa else card(card_id)
	return str(definition.get("name", card_id))

func dispersal_sources(player_id: int = -1) -> Array:
	var p := current_player if player_id == -1 else player_id
	var result: Array = []
	if players[p]["queen"] != Tri.INVALID:
		result.append({"type": "queen", "slot": -1, "coord": players[p]["queen"], "count": queen_spore_count(p)})
	for i in range(board_count):
		var slot: Dictionary = players[p]["slots"][i]
		if slot["active"].is_empty() or int(slot["dispersals"]) >= 2 or is_mushroom_blocked(p, i):
			continue
		var coord := find_mushroom(p, i)
		if coord != Tri.INVALID:
			result.append({"type": "mushroom", "slot": i, "coord": coord, "count": mushroom_spore_count(p, i)})
	return result

func spore_supply(player_id: int) -> int:
	var used := 0
	for tile in tiles.values():
		used += int(tile["spores"][player_id])
	return 30 - used

func queen_spore_count(player_id: int = -1) -> int:
	return 3 if has_bonus("queen_spores_3", player_id) else 2

func mushroom_spore_count(player_id: int, slot: int) -> int:
	var card_id: String = players[player_id]["slots"][slot]["active"]
	var definition := automa_card(card_id) if players[player_id]["is_automa"] else card(card_id)
	var count := int(definition.get("spores", definition.get("spores_" + automa_difficulty, 2)))
	if has_bonus("mushroom_spores_plus1", player_id, slot):
		count += 1
	return count

func begin_dispersal(source_type: String, slot: int = -1, wind: int = -1) -> bool:
	if not can_use_action("disperse") or not dispersal.is_empty() or spore_supply(current_player) <= 0:
		return false
	var chosen: Dictionary = {}
	for source in dispersal_sources():
		if source["type"] == source_type and int(source["slot"]) == slot:
			chosen = source
			break
	if chosen.is_empty():
		return false
	if wind < 0 or wind > 2:
		wind = rng.randi_range(0, 2)
	var queue: Array = [chosen]
	if source_type == "mushroom" and has_bonus("dual_disperse", current_player, slot):
		queue.append({"type": "queen", "slot": -1, "coord": current()["queen"], "count": queen_spore_count()})
	dispersal = {"queue": queue, "queue_index": 0, "wind": wind}
	_load_dispersal_source()
	_log("%s: ветер %s, источник — %s." % [current()["name"], Tri.WIND_NAMES[wind], "царица" if source_type == "queen" else "гриб %d" % (slot + 1)])
	changed.emit()
	return true

func _load_dispersal_source() -> void:
	var source: Dictionary = dispersal["queue"][dispersal["queue_index"]]
	var coord: Vector3i = source["coord"]
	if source["type"] == "queen":
		coord = current()["queen"]
		source["coord"] = coord
	else:
		coord = find_mushroom(current_player, source["slot"])
		source["coord"] = coord
	var layers := Tri.dispersal_layers(tiles, coord, tiles[coord]["rotation"], dispersal["wind"])
	dispersal["origin"] = coord
	dispersal["remaining"] = mini(int(source["count"]), spore_supply(current_player))
	dispersal["layers"] = layers
	dispersal["layer"] = 0
	dispersal["placed"] = {}
	dispersal["source_type"] = source["type"]
	dispersal["slot"] = source["slot"]

func get_dispersal_choices() -> Array[Vector3i]:
	var empty: Array[Vector3i] = []
	if dispersal.is_empty():
		return empty
	while int(dispersal["layer"]) < dispersal["layers"].size():
		var layer: Array = dispersal["layers"][dispersal["layer"]]
		var choices: Array[Vector3i] = []
		for coord in layer:
			if not dispersal["placed"].has(coord):
				choices.append(coord)
		if not choices.is_empty():
			return choices
		dispersal["layer"] += 1
	return empty

func place_dispersal_spore(coord: Vector3i) -> bool:
	if dispersal.is_empty() or not coord in get_dispersal_choices() or int(dispersal["remaining"]) <= 0:
		return false
	tiles[coord]["spores"][current_player] += 1
	dispersal["placed"][coord] = true
	dispersal["remaining"] = int(dispersal["remaining"]) - 1
	if int(dispersal["remaining"]) <= 0 or get_dispersal_choices().is_empty():
		_complete_dispersal_source()
	changed.emit()
	return true

func _complete_dispersal_source() -> void:
	if dispersal["source_type"] == "mushroom":
		var slot: int = dispersal["slot"]
		current()["slots"][slot]["dispersals"] = int(current()["slots"][slot]["dispersals"]) + 1
	if int(dispersal["queue_index"]) + 1 < dispersal["queue"].size() and spore_supply(current_player) > 0:
		dispersal["queue_index"] = int(dispersal["queue_index"]) + 1
		_load_dispersal_source()
		_log("Бонус: царица развеивает споры в том же направлении.")
		return
	dispersal.clear()
	_consume_action("disperse")

func decomposable_slots(player_id: int = -1) -> Array[int]:
	var p := current_player if player_id == -1 else player_id
	var result: Array[int] = []
	for i in range(board_count):
		var slot: Dictionary = players[p]["slots"][i]
		if not slot["active"].is_empty() and int(slot["dispersals"]) >= 2 and not is_mushroom_blocked(p, i):
			result.append(i)
	return result

func perform_decompose(slot: int) -> bool:
	if not can_use_action("decompose") or not slot in decomposable_slots():
		return false
	var card_id: String = current()["slots"][slot]["active"]
	var coord := find_mushroom(current_player, slot)
	if coord != Tri.INVALID:
		tiles[coord]["mushroom"] = -1
		tiles[coord]["slot"] = -1
	current()["slots"][slot]["decomposed"].append(card_id)
	current()["slots"][slot]["active"] = ""
	current()["slots"][slot]["dispersals"] = 0
	_log("%s разлагает «%s»." % [current()["name"], definition_name(card_id, current()["is_automa"])])
	_apply_decomposition_effect(card_id, slot)
	_consume_action("decompose")
	_check_end_game()
	changed.emit()
	return true

func _apply_decomposition_effect(card_id: String, slot: int) -> void:
	var definition := automa_card(card_id) if current()["is_automa"] else card(card_id)
	var effect_id := str(definition.get("effect_id", ""))
	match effect_id:
		"gain_insect":
			if insect_supply > 0:
				insect_supply -= 1
				current()["insects"] += 1
				_log("Эффект: +1 жетон насекомого.")
		"draw_two_deck":
			if not current()["is_automa"]:
				for i in range(2): _draw_to_hand(current_player)
				_log("Демо-эффект: взято до 2 карт с верха колоды.")
		"queen_spores_3", "queen_move_3", "repeat_action", "development_draw_two_choose":
			_log("Постоянный бонус активен до конца партии: " + str(definition.get("effect_text", effect_id)))
		"mushroom_spores_plus1", "choose_wind", "dual_disperse":
			_log("Грибной бонус будет действовать на следующие грибы планшета %d." % (slot + 1))
		"":
			_log("У карты нет эффекта.")
		_:
			_log("ЗАГЛУШКА: эффект «%s» пока не автоматизирован." % effect_id)

func _check_end_game() -> void:
	var completed := true
	for slot in current()["slots"]:
		if slot["decomposed"].is_empty():
			completed = false
			break
	if not completed:
		return
	phase = "finished"
	actions_left = 0
	if not current()["is_automa"]:
		end_token_owner = current_player
	_log("Партия завершена: %s выполняет условие конца игры." % current()["name"])

func score_for(player_id: int) -> Dictionary:
	var player: Dictionary = players[player_id]
	var mushroom_points := 0
	for card_id in player["grown"]:
		mushroom_points += 5 if player["is_automa"] else int(card(card_id).get("points", 0))
	var insect_points: int = int(player["insects"]) / 2
	var end_points := board_count if end_token_owner == player_id and not player["is_automa"] else 0
	return {
		"mushrooms": mushroom_points, "insects": insect_points, "end_token": end_points,
		"total": mushroom_points + insect_points + end_points,
		"grown_count": player["grown"].size(), "insect_count": player["insects"]
	}

func ranking() -> Array:
	var result: Array = []
	for player in players:
		var score := score_for(player["id"])
		score["player"] = player["id"]
		score["name"] = player["name"]
		result.append(score)
	result.sort_custom(func(a: Dictionary, b: Dictionary):
		if a["total"] != b["total"]: return a["total"] > b["total"]
		if a["grown_count"] != b["grown_count"]: return a["grown_count"] > b["grown_count"]
		return a["insect_count"] > b["insect_count"]
	)
	return result

func end_turn() -> bool:
	if phase != "playing" or actions_left != 0 or not dispersal.is_empty() or not pending_development.is_empty():
		return false
	_refill_market()
	if current()["is_automa"] and not automa_current_card.is_empty():
		automa_discard.append(automa_current_card)
		automa_current_card = ""
	current_player = (current_player + 1) % players.size()
	if current_player == first_player:
		turn_number += 1
	actions_left = 2
	actions_used.clear()
	_log("— Ход %d: %s —" % [turn_number, current()["name"]])
	changed.emit()
	return true

func perform_insect_refresh() -> bool:
	if phase != "playing" or current()["insects"] < 1 or current()["is_automa"]:
		return false
	current()["insects"] -= 1
	insect_supply += 1
	for card_id in market:
		if not str(card_id).is_empty(): deck.append(str(card_id))
	market.clear()
	for i in range(3): market.append(_draw_deck())
	_log("%s тратит 1 жетон и обновляет рынок." % current()["name"])
	changed.emit()
	return true

func perform_insect_move_queen(target_player: int, destination: Vector3i) -> bool:
	if phase != "playing" or current()["insects"] < 2 or target_player == current_player:
		return false
	if target_player < 0 or target_player >= players.size() or not tiles.has(destination) or queen_at(destination) != -1:
		return false
	current()["insects"] -= 2
	insect_supply += 2
	players[target_player]["queen"] = destination
	_collect_insect(destination, target_player)
	_log("%s перемещает чужую царицу за 2 жетона." % current()["name"])
	changed.emit()
	return true

func perform_exchange_cards(card_ids: Array) -> bool:
	if phase != "playing" or current()["is_automa"] or card_ids.size() != 3 or insect_supply <= 0:
		return false
	var unique := {}
	for card_id in card_ids:
		if not card_id in current()["hand"] or unique.has(card_id):
			return false
		unique[card_id] = true
	for card_id in card_ids:
		current()["hand"].erase(card_id)
		deck.append(card_id) # Под низ колоды.
	current()["insects"] += 1
	insect_supply -= 1
	_log("%s сбрасывает 3 карты и получает насекомое (без действия)." % current()["name"])
	changed.emit()
	return true

func _draw_automa_card() -> String:
	if automa_deck.is_empty():
		automa_deck = automa_discard.duplicate()
		automa_discard.clear()
		_shuffle(automa_deck)
	if automa_deck.is_empty():
		return ""
	automa_current_card = str(automa_deck.pop_front())
	_log("Автома раскрывает: %s." % definition_name(automa_current_card, true))
	return automa_current_card

func _automa_growth() -> bool:
	if not can_use_action("grow"):
		return false
	var options := find_growth_options(automa_current_card)
	if options.is_empty():
		return false
	var best: Dictionary = options[0]
	var best_score := -1
	for option in options:
		var score := 0
		for resource in option["payment"]:
			score += int(tiles[resource["coord"]]["spores"][resource["owner"]])
		if score > best_score:
			best_score = score
			best = option
	var costs: Array = automa_card(automa_current_card).get("cost", [])
	var target: Vector3i = best["targets"][0]
	for candidate in best["targets"]:
		if tiles[candidate]["color"] in costs:
			target = candidate
			break
	return perform_growth(automa_current_card, best["payment"], target, int(best["slot"]))

func _automa_decompose() -> bool:
	var slots := decomposable_slots()
	return perform_decompose(slots[0]) if not slots.is_empty() else false

func _automa_dispersal_source() -> Dictionary:
	var mushrooms: Array = []
	var any_mushrooms := false
	for slot in range(board_count):
		if find_mushroom(current_player, slot) != Tri.INVALID:
			any_mushrooms = true
	for source in dispersal_sources():
		if source["type"] == "mushroom": mushrooms.append(source)
	if not mushrooms.is_empty():
		mushrooms.sort_custom(func(a: Dictionary, b: Dictionary):
			return int(current()["slots"][a["slot"]]["dispersals"]) < int(current()["slots"][b["slot"]]["dispersals"])
		)
		return mushrooms[0]
	if not any_mushrooms:
		for source in dispersal_sources():
			if source["type"] == "queen": return source
	return {}

func _automa_explore_near(coord: Vector3i) -> bool:
	for stack in range(2):
		if tile_stacks[stack].is_empty(): continue
		for candidate in exploration_choices():
			if Tri.adjacent(candidate, coord):
				return perform_explore(stack, candidate)
	return false

func _automa_disperse() -> bool:
	if not can_use_action("disperse"):
		return false
	var source := _automa_dispersal_source()
	if source.is_empty(): return false
	# На крайнем тайле автома сначала обязана сделать разведку.
	if Tri.neighbors(source["coord"], tiles).size() == 1 and can_use_action("explore"):
		if _automa_explore_near(source["coord"]):
			return true
	if not begin_dispersal(source["type"], source["slot"]):
		return false
	var safety := 0
	while not dispersal.is_empty() and safety < 100:
		safety += 1
		var choices := get_dispersal_choices()
		if choices.is_empty(): break
		place_dispersal_spore(choices[0])
	if not dispersal.is_empty():
		# Страховка от некорректных пользовательских данных: завершаем доступную часть.
		while not dispersal.is_empty():
			_complete_dispersal_source()
	return true

func _automa_target_coords() -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var definition := automa_card(automa_current_card)
	var target := str(definition.get("move_target", "opponent_mushroom"))
	for coord in tiles:
		var include := false
		match target:
			"opponent_mushroom": include = tiles[coord]["mushroom"] != -1 and tiles[coord]["mushroom"] != current_player
			"own_mushroom": include = tiles[coord]["mushroom"] == current_player
			"insect": include = tiles[coord]["insect"]
			"opponent_spores":
				for p in range(players.size()):
					if p != current_player and tiles[coord]["spores"][p] > 0: include = true
			"opponent_queen": include = queen_at(coord, current_player) != -1
		if include: result.append(coord)
	return result

func _automa_move() -> bool:
	if not can_use_action("move"): return false
	var blocked := {}
	for player in players:
		if player["id"] != current_player and player["queen"] != Tri.INVALID:
			blocked[player["queen"]] = true
	var start: Vector3i = current()["queen"]
	var best_path: Array[Vector3i] = []
	for target in _automa_target_coords():
		var goals: Array[Vector3i] = [target]
		if queen_at(target, current_player) != -1:
			goals = Tri.neighbors(target, tiles)
		for goal in goals:
			if blocked.has(goal): continue
			var path := Tri.distance_path(tiles, start, goal, blocked)
			if path.size() > 1 and (best_path.is_empty() or path.size() < best_path.size()):
				best_path = path
	if not best_path.is_empty():
		var steps: Array = []
		for i in range(1, mini(best_path.size(), max_move_steps() + 1)):
			steps.append(best_path[i])
		return perform_move(steps)
	# Если цель недостижима — до двух шагов по случайным направлениям ветра.
	var steps: Array = []
	var position := start
	for i in range(2):
		var wind := rng.randi_range(0, 2)
		var edge := Tri.edge_for_wind(position, tiles[position]["rotation"], wind)
		var shared: Array = Tri.edges(position)[edge]
		var moved := false
		for other in Tri.neighbors(position, tiles):
			var shared_vertices := Tri.shared_vertices(position, other)
			if shared_vertices.size() == 2 and shared[0] in shared_vertices and shared[1] in shared_vertices and not blocked.has(other):
				steps.append(other)
				position = other
				moved = true
				break
		if not moved: break
	if not steps.is_empty(): return perform_move(steps)
	return false

func run_automa_turn() -> void:
	## Официальный порядок приоритетов; параметры раскрытой карты — заменяемые заглушки.
	if phase != "playing" or not current()["is_automa"]: return
	if automa_current_card.is_empty(): _draw_automa_card()
	var safety := 0
	while phase == "playing" and actions_left > 0 and safety < 12:
		safety += 1
		if _automa_growth(): continue
		if _automa_decompose(): continue
		if _automa_disperse(): continue
		if _automa_move(): continue
		if can_use_action("explore"):
			var choices := exploration_choices()
			for stack in range(2):
				if not choices.is_empty() and not tile_stacks[stack].is_empty() and perform_explore(stack, choices[0]):
					break
			if actions_used.has("explore"): continue
		_log("Автома: доступных автоматизированных действий больше нет; ход завершён досрочно.")
		actions_left = 0
	if phase == "playing" and actions_left == 0:
		end_turn()
	changed.emit()

func _log(text: String) -> void:
	game_log.append(text)
	if game_log.size() > 100:
		game_log.pop_front()
	notified.emit(text)

func to_dict() -> Dictionary:
	var saved_players: Array = []
	for player in players:
		var copy: Dictionary = player.duplicate(true)
		copy["queen"] = Tri.tile_to_string(player["queen"])
		saved_players.append(copy)
	var saved_tiles: Array = []
	for coord in tiles:
		var copy: Dictionary = tiles[coord].duplicate(true)
		copy["coord"] = Tri.tile_to_string(coord)
		saved_tiles.append(copy)
	var central: Array = []
	for coord in central_tiles: central.append(Tri.tile_to_string(coord))
	return {
		"version": 1, "players": saved_players, "tiles": saved_tiles,
		"tile_stacks": tile_stacks.duplicate(true), "central_tiles": central,
		"deck": deck.duplicate(), "market": market.duplicate(),
		"automa_deck": automa_deck.duplicate(), "automa_discard": automa_discard.duplicate(),
		"automa_current_card": automa_current_card, "automa_difficulty": automa_difficulty,
		"human_count": human_count, "board_count": board_count, "insect_supply": insect_supply,
		"current_player": current_player, "first_player": first_player, "phase": phase,
		"actions_left": actions_left, "actions_used": actions_used.duplicate(),
		"setup_order": setup_order.duplicate(), "setup_cursor": setup_cursor,
		"turn_number": turn_number, "end_token_owner": end_token_owner,
		"game_log": game_log.duplicate(), "rng_state": str(rng.state),
		"pending_development": pending_development.duplicate(true)
	}

func save_game(path: String = "user://micely_save.json") -> Error:
	if not dispersal.is_empty():
		return ERR_BUSY
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict(), "\t"))
	return OK

func load_game(path: String = "user://micely_save.json") -> Error:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return FileAccess.get_open_error()
	var data = JSON.parse_string(file.get_as_text())
	if not data is Dictionary or int(data.get("version", 0)) != 1:
		return ERR_INVALID_DATA
	load_components()
	players = data["players"]
	for player in players:
		player["queen"] = Tri.tile_from_string(player["queen"])
	tiles.clear()
	for saved in data["tiles"]:
		var coord := Tri.tile_from_string(saved["coord"])
		var tile: Dictionary = saved.duplicate(true)
		tile.erase("coord")
		# JSON числа приходят float; индексы игроков обязаны оставаться int.
		tile["mushroom"] = int(tile["mushroom"])
		tile["slot"] = int(tile["slot"])
		tile["rotation"] = int(tile["rotation"])
		var int_spores: Array = []
		for value in tile["spores"]: int_spores.append(int(value))
		tile["spores"] = int_spores
		tiles[coord] = tile
	tile_stacks = data["tile_stacks"]
	central_tiles.clear()
	for value in data["central_tiles"]: central_tiles.append(Tri.tile_from_string(value))
	deck = data["deck"]
	market = data["market"]
	automa_deck = data["automa_deck"]
	automa_discard = data["automa_discard"]
	automa_current_card = data["automa_current_card"]
	automa_difficulty = data["automa_difficulty"]
	human_count = int(data["human_count"])
	board_count = int(data["board_count"])
	insect_supply = int(data["insect_supply"])
	current_player = int(data["current_player"])
	first_player = int(data["first_player"])
	phase = data["phase"]
	actions_left = int(data["actions_left"])
	actions_used = data["actions_used"]
	setup_order = data["setup_order"]
	setup_cursor = int(data["setup_cursor"])
	turn_number = int(data["turn_number"])
	end_token_owner = int(data["end_token_owner"])
	game_log.clear()
	for line in data.get("game_log", []): game_log.append(str(line))
	rng.state = int(data.get("rng_state", "0"))
	pending_development = data.get("pending_development", {})
	dispersal.clear()
	changed.emit()
	_log("Сохранение загружено.")
	return OK
