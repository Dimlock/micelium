extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("UI TEST: " + message)

func run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	check(is_instance_valid(scene.menu_players), "menu built")
	scene._start_from_menu()
	await process_frame
	await process_frame
	check(is_instance_valid(scene.board), "game board built")
	check(scene.game.tiles.size() == 12, "initial board visible model")
	while scene.game.phase == "queens":
		scene._on_tile_clicked(scene.game.initial_queen_choices()[0])
		await process_frame
	check(scene.game.phase == "playing", "queen placement through UI handler")
	scene._on_action("develop")
	await process_frame
	scene._on_develop_deck()
	await process_frame
	check(scene.game.actions_left == 1, "development through UI handler")
	scene._on_action("move")
	await process_frame
	var neighbors: Array = scene._move_neighbors()
	check(not neighbors.is_empty(), "movement highlights generated")
	if not neighbors.is_empty():
		scene._on_tile_clicked(neighbors[0])
		scene._finish_move()
	await process_frame
	check(scene.game.actions_left == 0, "movement confirmed through UI handler")
	scene._end_turn()
	await process_frame
	check(scene.game.current_player == 1, "turn passes through UI handler")
	scene.bottom_tabs.current_tab = 2
	await process_frame
	scene.bottom_tabs.current_tab = 3
	await process_frame
	print("UI SMOKE: ", failures, " failures")
	scene.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
