extends SceneTree
## Стресс-тест полных партий детерминированным автопилотом (не эталонный ИИ).
## Тупик ресурсов не считается ошибкой: в PDF нет правила досрочного завершения
## при занятых планшетах и нулевом запасе спор. Завершение партий проверяем отдельно.

const Game = preload("res://scripts/game_state.gd")
const Tri = preload("res://scripts/triangle_grid.gd")
var failures := 0
var completed_four := 0
var completed_solo := 0
var stalled := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for seed_index in range(5):
		simulate(4, false, "four-" + str(seed_index))
	for seed_index in range(3):
		simulate(1, true, "solo-" + str(seed_index))
	if completed_four == 0:
		failures += 1
		push_error("SIMULATION: ни одна партия на четверых не завершилась")
	if completed_solo == 0:
		failures += 1
		push_error("SIMULATION: ни одна одиночная партия не завершилась")
	print("SIMULATION: ", completed_four + completed_solo, " completed, ", stalled, " resource stalls, ", failures, " failures")
	quit(1 if failures > 0 else 0)

func simulate(humans: int, automa: bool, seed_text: String) -> void:
	var game := Game.new()
	game.new_game(humans, 3, automa, seed_text)
	while game.phase == "queens":
		if game.current()["is_automa"]:
			game.place_initial_queen(game.choose_automa_initial_queen())
		else:
			game.place_initial_queen(game.initial_queen_choices()[0])
	var turns := 0
	while game.phase != "finished" and turns < 500:
		turns += 1
		if game.current()["is_automa"]:
			game.run_automa_turn()
			continue
		var safety := 0
		while game.phase == "playing" and game.actions_left > 0 and safety < 10:
			safety += 1
			if do_decompose(game): continue
			if do_grow(game): continue
			if do_disperse(game): continue
			if do_develop(game): continue
			if do_explore(game): continue
			if game.deck.is_empty() and game.current()["hand"].size() >= 3 and (game.insect_supply > 0 or game.current()["insects"] > 0):
				if game.insect_supply == 0: game.perform_insect_refresh()
				game.perform_exchange_cards(game.current()["hand"].slice(0, 3))
				if do_grow(game): continue
				if do_develop(game): continue
			if do_move(game): continue
			game.actions_left = 0
		if game.phase == "playing" and game.actions_left == 0:
			game.end_turn()
	if game.phase != "finished":
		stalled += 1
		print("SIM STALL ",seed_text," (ресурсный тупик автопилота, не сбой движка)")
	else:
		if humans == 4: completed_four += 1
		else: completed_solo += 1
		var winner: Dictionary = game.ranking()[0]
		print("SIM OK ",seed_text," turns=",turns," winner=",winner["name"]," score=",winner["total"])

func do_decompose(game: MyceliumGame) -> bool:
	var slots := game.decomposable_slots()
	return game.perform_decompose(slots[0]) if not slots.is_empty() else false

func do_grow(game: MyceliumGame) -> bool:
	if not game.can_use_action("grow"): return false
	for card_id in game.current()["hand"].duplicate():
		var options := game.find_growth_options(card_id)
		if not options.is_empty():
			return game.perform_growth(card_id, options[0]["payment"], options[0]["targets"][0])
	return false

func do_disperse(game: MyceliumGame) -> bool:
	if not game.can_use_action("disperse"): return false
	var sources := game.dispersal_sources()
	sources.sort_custom(func(a: Dictionary, b: Dictionary):
		if a["type"] != b["type"]: return a["type"] == "mushroom"
		return int(a["slot"]) < int(b["slot"])
	)
	if sources.is_empty(): return false
	# Царица не сжигает последний резерв; грибы продолжают цикл разложения.
	if sources[0]["type"] == "queen" and game.spore_supply(game.current_player) < 12: return false
	var wind := posmod(game.turn_number + game.current_player + game.actions_left, 3)
	if not game.begin_dispersal(sources[0]["type"], sources[0]["slot"], wind): return false
	var safety := 0
	while not game.dispersal.is_empty() and safety < 50:
		safety += 1
		var choices := game.get_dispersal_choices()
		if choices.is_empty(): return false
		game.place_dispersal_spore(choices[0])
	return game.dispersal.is_empty()

func do_develop(game: MyceliumGame) -> bool:
	if not game.can_use_action("develop"): return false
	if game.deck.is_empty():
		for i in range(game.market.size()):
			if not str(game.market[i]).is_empty():
				return game.perform_develop_market(i)
	if not game.perform_develop_deck(): return false
	if not game.pending_development.is_empty():
		game.choose_development(game.pending_development["cards"][0])
	return true

func do_explore(game: MyceliumGame) -> bool:
	if not game.can_use_action("explore"): return false
	var frontier := game.exploration_choices()
	for stack in range(2):
		if not frontier.is_empty() and not game.tile_stacks[stack].is_empty():
			return game.perform_explore(stack, frontier[0])
	return false

func do_move(game: MyceliumGame) -> bool:
	if not game.can_use_action("move"): return false
	var start: Vector3i = game.current()["queen"]
	for coord in Tri.neighbors(start, game.tiles):
		if game.queen_at(coord, game.current_player) == -1:
			return game.perform_move([coord])
	return false
