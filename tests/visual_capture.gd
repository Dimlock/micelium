extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func capture(path: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(path)

func run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await create_timer(0.3).timeout
	await capture("res://tests/menu_capture.png")
	scene._start_from_menu()
	await create_timer(0.3).timeout
	while scene.game.phase == "queens":
		scene._on_tile_clicked(scene.game.initial_queen_choices()[0])
		await process_frame
	scene.board.fit_board()
	await create_timer(0.3).timeout
	var main_layout = scene.screen_root.get_child(1)
	var content_layout = main_layout.get_child(1)
	print("ROOT ",root.size," SCENE ",scene.size," MAIN ",main_layout.size," MIN ",main_layout.get_combined_minimum_size())
	print("CONTENT ",content_layout.size," MIN ",content_layout.get_combined_minimum_size()," BOARD ",scene.board.size)
	print("SIDEBAR ",content_layout.get_child(1).size," MIN ",content_layout.get_child(1).get_combined_minimum_size())
	print("BOTTOM ",main_layout.get_child(2).size," MIN ",main_layout.get_child(2).get_combined_minimum_size())
	var side_column = content_layout.get_child(1).get_child(0)
	for child in side_column.get_children(): print("SIDE ",child.get_class()," ",child.size," MIN ",child.get_combined_minimum_size())
	await capture("res://tests/game_capture.png")
	print("CAPTURES SAVED")
	quit()
