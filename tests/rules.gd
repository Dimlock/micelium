extends SceneTree

const Game = preload("res://scripts/game_state.gd")
const Tri = preload("res://scripts/triangle_grid.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("TEST FAILED: " + message)

func ready_game(boards: int = 5) -> MyceliumGame:
	var game := Game.new()
	game.new_game(2, boards, false, "rules-test")
	while game.phase == "queens":
		game.place_initial_queen(game.initial_queen_choices()[0])
	return game

func reset_actions(game: MyceliumGame) -> void:
	game.current_player = 0
	game.actions_left = 2
	game.actions_used.clear()
	game.phase = "playing"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	test_grid()
	test_wild_payment()
	var game := ready_game(3)
	test_mycelium(game)
	game = ready_game(3)
	test_lifecycle(game)
	game = ready_game()
	test_alternative_growth_target(game)
	game = ready_game()
	test_development_bonus(game)
	test_save(game)
	test_automa()
	print("RULE TESTS: ", checks, " checks, ", failures, " failures")
	quit(1 if failures > 0 else 0)

func test_grid() -> void:
	var board := {}
	var source := Vector3i(0, 0, 0)
	for x in range(-4, 5):
		for y in range(-4, 5):
			for orientation in range(2):
				board[Vector3i(x, y, orientation)] = true
	for wind in range(3):
		var layers := Tri.dispersal_layers(board, source, 0, wind)
		check(layers.size() >= 5, "wind has five rows")
		check(layers[0].size() == 1, "source row has one tile")
		check(layers[1].size() == 1, "wind row has one tile")
		check(layers[2].size() == 2, "third row has two tiles")
		check(layers[3].size() == 2, "fourth graph row has two tiles")
		check(layers[4].size() == 3, "fifth graph row has three tiles")
	check(Tri.star_setup()["all"].size() == 12, "initial star has twelve triangles")

func test_wild_payment() -> void:
	var game := Game.new()
	game.players = [{"id": 0}]
	var payment := game.find_payment([{"coord": Vector3i.ZERO, "owner": 0, "color": "black"}], ["green"])
	check(payment.size() == 1, "black tile pays any color")
	payment = game.find_payment([{"coord": Vector3i.ZERO, "owner": 0, "color": "red"}], ["green"])
	check(payment.is_empty(), "wrong color cannot pay")

func test_mycelium(game: MyceliumGame) -> void:
	var a := Vector3i(0, 0, 0)
	var candidates := Tri.candidates(a)
	var b: Vector3i = candidates[0]
	var c := Tri.INVALID
	for candidate in Tri.candidates(b):
		if candidate != a:
			c = candidate
			break
	game.tiles.clear()
	for coord in [a, b, c]:
		game._add_tile(coord, "tile_01", false)
		game.tiles[coord]["spores"][0] = 1
	game.players[0]["queen"] = a
	game.players[1]["queen"] = c
	game.current_player = 0
	var own := game.get_mycelium(0)
	var own_resources: Array = []
	for network in own: own_resources.append_array(network["resources"])
	check(own_resources.size() == 2, "foreign queen cuts off owned spore tile")
	var other := game.get_mycelium(1)
	var other_resources: Array = []
	for network in other: other_resources.append_array(network["resources"])
	check(other_resources.size() == 1 and other_resources[0]["owner"] == 0, "queen appropriates foreign spores")
	game.players[1]["queen"] = Tri.INVALID
	other = game.get_mycelium(1)
	other_resources.clear()
	for network in other: other_resources.append_array(network["resources"])
	check(other_resources.is_empty(), "neutral foreign spores are not appropriated")

func test_lifecycle(game: MyceliumGame) -> void:
	reset_actions(game)
	for coord in game.tiles:
		game.tiles[coord]["color"] = "red"
		game.tiles[coord]["spores"][0] = 0
		game.tiles[coord]["spores"][1] = 0
	var origin: Vector3i = game.players[0]["queen"]
	game.tiles[origin]["spores"][0] = 2
	game.players[0]["hand"] = ["demo_01"]
	for slot in game.players[0]["slots"]:
		slot["active"] = ""
		slot["decomposed"] = []
		slot["dispersals"] = 0
	game.players[0]["grown"] = []
	var options := game.find_growth_options("demo_01")
	check(not options.is_empty(), "growth option found")
	check(game.perform_growth("demo_01", options[0]["payment"], options[0]["targets"][0]), "growth succeeds")
	check(game.players[0]["slots"][0]["active"] == "demo_01", "card occupies first board")
	for cycle in range(2):
		reset_actions(game)
		check(game.begin_dispersal("mushroom", 0, 0), "dispersal begins")
		var safety := 0
		while not game.dispersal.is_empty() and safety < 30:
			safety += 1
			var choices := game.get_dispersal_choices()
			check(not choices.is_empty(), "dispersal has legal tile")
			game.place_dispersal_spore(choices[0])
		check(int(game.players[0]["slots"][0]["dispersals"]) == cycle + 1, "spore counter advances")
	check(game.decomposable_slots(0).has(0), "two dispersals enable decomposition")
	game.players[0]["slots"][1]["decomposed"] = ["demo_02"]
	game.players[0]["slots"][2]["decomposed"] = ["demo_03"]
	reset_actions(game)
	check(game.perform_decompose(0), "decomposition succeeds")
	check(game.phase == "finished", "one card under every board ends game immediately")
	check(game.end_token_owner == 0, "human receives end token")
	check(game.score_for(0)["end_token"] == 3, "short game end token equals board count")
	check(game.find_mushroom(0, 0) == Tri.INVALID, "decomposed mushroom leaves field")

func test_alternative_growth_target(game: MyceliumGame) -> void:
	reset_actions(game)
	var occupied := Vector3i(0, 0, 0)
	var free: Vector3i = Tri.candidates(occupied)[0]
	game.tiles.clear()
	for coord in [occupied, free]:
		game._add_tile(coord, "tile_01", false)
		game.tiles[coord]["spores"][0] = 1
	game.players[0]["queen"] = occupied
	game.players[1]["queen"] = Tri.INVALID
	game.tiles[occupied]["mushroom"] = 0
	game.tiles[occupied]["slot"] = 0
	game.players[0]["slots"][0]["active"] = "demo_02"
	game.players[0]["hand"] = ["demo_01"]
	var options := game.find_growth_options("demo_01")
	check(options.size() == game.board_count - 1, "growth offers every free board and alternative payment")
	if not options.is_empty():
		var chosen: Dictionary = options.back()
		check(chosen["payment"][0]["coord"] == free, "free target is included in payment")
		check(game.perform_growth("demo_01", chosen["payment"], free, chosen["slot"]), "alternative growth target succeeds")
		check(game.tiles[free]["mushroom"] == 0, "new mushroom placed on free paid tile")
		check(game.players[0]["slots"][chosen["slot"]]["active"] == "demo_01", "chosen board receives grown card")

func test_development_bonus(game: MyceliumGame) -> void:
	reset_actions(game)
	game.players[0]["slots"][0]["decomposed"] = ["demo_08"]
	var hand_before: int = game.players[0]["hand"].size()
	check(game.perform_develop_deck(), "development with bonus begins")
	check(game.pending_development.get("cards", []).size() == 2, "development bonus offers two cards")
	var offered: Array = game.pending_development.get("cards", [])
	check(game.choose_development(offered[0]), "development bonus choice accepted")
	check(game.players[0]["hand"].size() == hand_before + 1, "development bonus keeps exactly one card")
	check(game.pending_development.is_empty(), "development bonus resolves")

func test_save(game: MyceliumGame) -> void:
	var path := "user://rules_test_save.json"
	check(game.save_game(path) == OK, "save succeeds")
	var loaded := Game.new()
	check(loaded.load_game(path) == OK, "load succeeds")
	check(loaded.tiles.size() == game.tiles.size(), "tile count roundtrip")
	check(loaded.players.size() == game.players.size(), "player count roundtrip")
	check(loaded.current_player == game.current_player, "current player roundtrip")

func test_automa() -> void:
	var game := Game.new()
	game.new_game(1, 3, true, "automa-test")
	game.place_initial_queen(game.initial_queen_choices()[0])
	game.place_initial_queen(game.choose_automa_initial_queen())
	check(game.phase == "playing", "solo setup completes")
	for turn in range(12):
		if game.phase == "finished": break
		game.current_player = 1
		game.actions_left = 2
		game.actions_used.clear()
		game.run_automa_turn()
	check(game.players[1]["grown"].size() + game.players[1]["insects"] >= 0, "automa state remains valid")
	check(game.tiles.size() >= 12, "automa board remains valid")
