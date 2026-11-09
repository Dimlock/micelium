extends Control
## Экран меню, локальный hot-seat UI и обработка хода автомы.

const Game = preload("res://scripts/game_state.gd")
const Board = preload("res://scripts/board_view.gd")
const Card = preload("res://scripts/card_view.gd")
const Tri = preload("res://scripts/triangle_grid.gd")

var game := Game.new()
var board
var screen_root: Control
var turn_label: Label
var round_label: Label
var player_label: Label
var stats_label: Label
var status_label: Label
var context_instructions: Label
var context_controls: VBoxContainer
var log_view: RichTextLabel
var action_buttons: Dictionary = {}
var end_turn_button: Button
var bottom_tabs: TabContainer
var hand_container: HBoxContainer
var market_container: HBoxContainer
var slots_container: HBoxContainer
var players_container: VBoxContainer
var deck_count_label: Label

var mode := ""
var selected_card_id := ""
var selected_slot := -1
var selected_tile := Tri.INVALID
var move_path: Array[Vector3i] = []
var explore_stack := -1
var growth_card_id := ""
var growth_options: Array = []
var growth_option: Dictionary = {}
var pending_source: Dictionary = {}
var exchange_mode := false
var exchange_selection: Array = []
var insect_target := -1
var last_message := "Выберите действие."
var automa_running := false
var session_serial := 0
var results_shown := false

var menu_players: OptionButton
var menu_boards: OptionButton
var menu_automa: CheckBox
var menu_difficulty: OptionButton
var menu_seed: LineEdit

func _ready() -> void:
	_build_theme()
	game.changed.connect(_on_game_changed)
	game.notified.connect(_on_game_notified)
	show_menu()

func _build_theme() -> void:
	var app_theme := Theme.new()
	app_theme.default_font_size = 16
	app_theme.set_color("font_color", "Label", Color("#e8e5d7"))
	app_theme.set_color("font_color", "Button", Color("#eee9d9"))
	app_theme.set_color("font_disabled_color", "Button", Color("#758078"))
	app_theme.set_stylebox("normal", "Button", _style(Color("#294036"), Color("#526b5a"), 8))
	app_theme.set_stylebox("hover", "Button", _style(Color("#385344"), Color("#8aa883"), 8))
	app_theme.set_stylebox("pressed", "Button", _style(Color("#49634c"), Color("#c0d5a5"), 8))
	app_theme.set_stylebox("disabled", "Button", _style(Color("#202b26"), Color("#34443b"), 8))
	app_theme.set_stylebox("panel", "PanelContainer", _style(Color("#1b2a24"), Color("#344c3e"), 12))
	app_theme.set_stylebox("panel", "Panel", _style(Color("#1b2a24"), Color("#344c3e"), 12))
	theme = app_theme

func _style(background: Color, border: Color, radius: int = 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func _full_rect(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _clear_node(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func show_menu() -> void:
	session_serial += 1
	automa_running = false
	mode = ""
	if is_instance_valid(screen_root):
		remove_child(screen_root)
		screen_root.queue_free()
	screen_root = Control.new()
	add_child(screen_root)
	_full_rect(screen_root)
	var background := ColorRect.new()
	background.color = Color("#101c17")
	screen_root.add_child(background)
	_full_rect(background)
	var decoration := MyceliumMenuArt.new()
	screen_root.add_child(decoration)
	_full_rect(decoration)
	var margin := MarginContainer.new()
	screen_root.add_child(margin)
	_full_rect(margin)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 42)
	var center := CenterContainer.new()
	margin.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(670, 0)
	panel.add_theme_stylebox_override("panel", _style(Color("#1d3027"), Color("#6d8467"), 18))
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 13)
	panel.add_child(content)
	var eyebrow := _label("ЦИФРОВОЙ ПРОТОТИП · GODOT 4", 13, Color("#b7c69f"))
	content.add_child(eyebrow)
	var title := _label("МИЦЕЛИЙ", 54, Color("#f0d490"))
	content.add_child(title)
	var subtitle := _label("Выращивайте грибы. Развевайте споры.\nПусть ваша грибница переживёт конкурентов.", 19, Color("#d7dfcf"))
	content.add_child(subtitle)
	var warning := _label("Компоненты — редактируемые демо-заглушки.\nЧисла на 69 картах и 10 картах автомы не заявлены как оригинальные.", 13, Color("#e0c789"))
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(warning)
	content.add_child(HSeparator.new())
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 12)
	content.add_child(grid)
	grid.add_child(_label("Живые игроки"))
	menu_players = OptionButton.new()
	for i in range(1, 5): menu_players.add_item("%d %s" % [i, "игрок" if i == 1 else "игрока"])
	menu_players.selected = 1
	menu_players.item_selected.connect(_on_menu_players_changed)
	grid.add_child(menu_players)
	grid.add_child(_label("Длина партии"))
	menu_boards = OptionButton.new()
	menu_boards.add_item("Обычная · 5 планшетов")
	menu_boards.add_item("Короткая · 4 планшета")
	menu_boards.add_item("Короткая · 3 планшета")
	grid.add_child(menu_boards)
	grid.add_child(_label("Сид (необязательно)"))
	menu_seed = LineEdit.new()
	menu_seed.placeholder_text = "Например: forest-42"
	grid.add_child(menu_seed)
	menu_automa = CheckBox.new()
	menu_automa.text = "Добавить автому (последним игроком)"
	menu_automa.tooltip_text = "Реализован порядок действий автомы; значения её карт — заглушки."
	content.add_child(menu_automa)
	menu_difficulty = OptionButton.new()
	menu_difficulty.add_item("Автома: средняя сложность")
	menu_difficulty.add_item("Автома: высокая сложность")
	menu_difficulty.disabled = true
	content.add_child(menu_difficulty)
	menu_automa.toggled.connect(func(value: bool): menu_difficulty.disabled = not value)
	var start := _button("Начать партию  →", _start_from_menu)
	start.custom_minimum_size.y = 52
	start.add_theme_font_size_override("font_size", 20)
	content.add_child(start)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	content.add_child(row)
	row.add_child(_button("Краткие правила", _show_rules))
	row.add_child(_button("Загрузить сохранение", _load_from_menu))
	var footer := _label("Локальный hot-seat · колесо мыши — масштаб · перетаскивание — панорама", 12, Color("#93a596"))
	content.add_child(footer)

func _on_menu_players_changed(index: int) -> void:
	if index == 3:
		menu_automa.button_pressed = false
	menu_automa.disabled = index == 3

func _start_from_menu() -> void:
	var humans: int = menu_players.selected + 1
	var boards: int = 5 - menu_boards.selected
	var with_automa: bool = menu_automa.button_pressed and humans < 4
	var difficulty := "hard" if menu_difficulty.selected == 1 else "medium"
	game.new_game(humans, boards, with_automa, menu_seed.text, difficulty)
	_build_game_screen(true)
	_schedule_automa()

func _build_game_screen(refit: bool = false) -> void:
	session_serial += 1
	if is_instance_valid(screen_root):
		remove_child(screen_root)
		screen_root.queue_free()
	screen_root = Control.new()
	add_child(screen_root)
	_full_rect(screen_root)
	var background := ColorRect.new()
	background.color = Color("#111c18")
	screen_root.add_child(background)
	_full_rect(background)
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 8)
	screen_root.add_child(main)
	_full_rect(main)
	main.offset_left = 10
	main.offset_top = 10
	main.offset_right = -10
	main.offset_bottom = -10
	_build_topbar(main)
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	main.add_child(content)
	board = Board.new()
	board.game = game
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.custom_minimum_size = Vector2(560, 380)
	board.tile_clicked.connect(_on_tile_clicked)
	content.add_child(board)
	_build_sidebar(content)
	_build_bottom(main)
	results_shown = false
	_reset_transient()
	refresh()
	if refit:
		board.call_deferred("fit_board")
		board.call_deferred("fit_board")

func _build_topbar(parent: VBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 58
	parent.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var title := _label("МИЦЕЛИЙ", 25, Color("#ecd08c"))
	row.add_child(title)
	var separator := VSeparator.new()
	row.add_child(separator)
	turn_label = _label("", 17)
	row.add_child(turn_label)
	round_label = _label("", 13, Color("#9fb0a1"))
	row.add_child(round_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(_button("Центрировать", func(): board.fit_board()))
	row.add_child(_button("Правила", _show_rules))
	row.add_child(_button("Сохранить", _save_game))
	row.add_child(_button("Загрузить", _load_game))
	row.add_child(_button("Меню", show_menu))

func _build_sidebar(parent: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 382
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	panel.add_child(column)
	player_label = _label("", 22, Color("#f0d28e"))
	column.add_child(player_label)
	stats_label = _label("", 12, Color("#b5c2b4"))
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(stats_label)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	column.add_child(grid)
	for action in Game.ACTIONS:
		var button := _button(Game.ACTION_NAMES[action], func(): _on_action(action))
		button.custom_minimum_size = Vector2(110, 36)
		button.add_theme_font_size_override("font_size", 13)
		grid.add_child(button)
		action_buttons[action] = button
	end_turn_button = _button("Завершить ход", _end_turn)
	column.add_child(end_turn_button)
	var context_panel := PanelContainer.new()
	context_panel.custom_minimum_size.y = 125
	context_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	context_panel.add_theme_stylebox_override("panel", _style(Color("#14231d"), Color("#3f5b47"), 8))
	column.add_child(context_panel)
	var context := VBoxContainer.new()
	context.add_theme_constant_override("separation", 7)
	context_panel.add_child(context)
	context_instructions = _label("", 13, Color("#d9ddce"))
	context_instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	context_instructions.size_flags_vertical = Control.SIZE_EXPAND_FILL
	context.add_child(context_instructions)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 90
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	context.add_child(scroll)
	context_controls = VBoxContainer.new()
	context_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	context_controls.add_theme_constant_override("separation", 5)
	scroll.add_child(context_controls)
	var insects_label := _label("БЕСПЛАТНЫЕ ОПЕРАЦИИ", 11, Color("#c7ad6c"))
	column.add_child(insects_label)
	var insects := HBoxContainer.new()
	insects.add_theme_constant_override("separation", 5)
	column.add_child(insects)
	var refresh_market := _button("Рынок · 1 ж", func():
		exchange_mode = false
		if not game.perform_insect_refresh(): _set_status("Нужен 1 жетон и обычный ход игрока.")
	)
	refresh_market.custom_minimum_size.x = 110
	insects.add_child(refresh_market)
	insects.add_child(_button("Царица · 2 ж", _start_insect_move))
	insects.add_child(_button("3 карты → ж", _toggle_exchange))
	column.add_child(HSeparator.new())
	status_label = _label("", 12, Color("#e0c789"))
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.y = 28
	column.add_child(status_label)
	log_view = RichTextLabel.new()
	log_view.bbcode_enabled = true
	log_view.scroll_active = true
	log_view.scroll_following = true
	log_view.custom_minimum_size.y = 55
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_view.add_theme_font_size_override("normal_font_size", 11)
	column.add_child(log_view)

func _build_bottom(parent: VBoxContainer) -> void:
	bottom_tabs = TabContainer.new()
	bottom_tabs.custom_minimum_size.y = 270
	bottom_tabs.size_flags_vertical = Control.SIZE_FILL
	parent.add_child(bottom_tabs)
	var hand_page := _make_tab("Рука")
	hand_container = _horizontal_scroll_page(hand_page)
	var market_page := _make_tab("Рынок")
	var market_column := VBoxContainer.new()
	market_page.add_child(market_column)
	deck_count_label = _label("", 12, Color("#b8c6b6"))
	market_column.add_child(deck_count_label)
	var market_scroll := ScrollContainer.new()
	market_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	market_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	market_column.add_child(market_scroll)
	market_container = HBoxContainer.new()
	market_container.add_theme_constant_override("separation", 12)
	market_scroll.add_child(market_container)
	var slots_page := _make_tab("Планшеты")
	slots_container = _horizontal_scroll_page(slots_page)
	var players_page := _make_tab("Игроки и очки")
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	players_page.add_child(scroll)
	players_container = VBoxContainer.new()
	players_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players_container.add_theme_constant_override("separation", 8)
	scroll.add_child(players_container)

func _make_tab(title: String) -> MarginContainer:
	var page := MarginContainer.new()
	page.name = title
	for side in ["left", "right", "top", "bottom"]:
		page.add_theme_constant_override("margin_" + side, 8)
	bottom_tabs.add_child(page)
	return page

func _horizontal_scroll_page(page: MarginContainer) -> HBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 9)
	scroll.add_child(row)
	return row

func refresh() -> void:
	if not is_instance_valid(board) or game.players.is_empty(): return
	var player: Dictionary = game.current()
	turn_label.text = player["name"]
	turn_label.add_theme_color_override("font_color", game.player_color(game.current_player))
	round_label.text = "Раунд %d · %s" % [game.turn_number, "подготовка" if game.phase == "queens" else "действий: %d" % game.actions_left]
	player_label.text = player["name"]
	player_label.add_theme_color_override("font_color", game.player_color(game.current_player))
	var score := game.score_for(game.current_player)
	stats_label.text = "Жетоны: %d · Споры в запасе: %d · Грибы: %d\nОчки: %d · Планшетов: %d · Общий запас жетонов: %d" % [
		player["insects"], game.spore_supply(game.current_player), player["grown"].size(), score["total"], game.board_count, game.insect_supply
	]
	var is_human_turn: bool = not player["is_automa"] and game.phase == "playing" and not automa_running
	for action in action_buttons:
		var button: Button = action_buttons[action]
		button.disabled = not is_human_turn or not game.can_use_action(action)
		button.text = ("✓ " if action in game.actions_used else "") + Game.ACTION_NAMES[action]
	end_turn_button.disabled = not is_human_turn or game.actions_left != 0 or not game.dispersal.is_empty() or not game.pending_development.is_empty()
	_update_context()
	_rebuild_hand()
	_rebuild_market()
	_rebuild_slots()
	_rebuild_players()
	_update_board()
	var lines: Array[String] = []
	for line in game.game_log.slice(maxi(0, game.game_log.size() - 18)):
		lines.append("[color=#b9c7b6]" + line.replace("[", "［") + "[/color]")
	log_view.text = "\n".join(lines)
	status_label.text = last_message
	if game.phase == "finished" and not results_shown:
		results_shown = true
		call_deferred("_show_results")

func _update_context() -> void:
	_clear_node(context_controls)
	var text := ""
	if game.phase == "queens":
		text = "Подготовка: %s, выберите один из подсвеченных центральных нечёрных тайлов." % game.current()["name"]
	elif game.phase == "finished":
		text = "Партия завершена. Итоги — во вкладке «Игроки и очки»."
	elif game.current()["is_automa"]:
		text = "Автома выполняет ход: выращивание → разложение → развеивание → перемещение."
		if not game.automa_current_card.is_empty():
			text += "\nКарта: " + game.definition_name(game.automa_current_card, true)
	elif not game.dispersal.is_empty():
		text = "Ветер: %s · осталось спор: %d\nНажимайте подсвеченные тайлы. Сначала заполните текущий ряд; пропускать обязательные споры нельзя." % [Tri.WIND_NAMES[game.dispersal["wind"]], game.dispersal["remaining"]]
	elif not game.pending_development.is_empty():
		text = "Бонус развития: оставьте одну карту, остальные уйдут под низ колоды."
		for card_id in game.pending_development["cards"]:
			context_controls.add_child(_button("Оставить: " + game.definition_name(card_id), func(): _choose_development(card_id)))
	else:
		match mode:
			"move":
				text = "Перемещение: выберите 1–%d последовательных тайла. Чужие царицы блокируют путь." % game.max_move_steps()
				var finish := _button("Подтвердить путь (%d шаг.)" % maxi(0, move_path.size() - 1), _finish_move)
				finish.disabled = move_path.size() < 2
				context_controls.add_child(finish)
				context_controls.add_child(_button("Сбросить путь", _start_move))
			"explore":
				text = "Разведка: выберите стопку, затем призрачную позицию рядом с полем."
				for i in range(2):
					var stack_button := _button("Стопка %d · %d тайлов" % [i + 1, game.tile_stacks[i].size()], func(): _select_explore_stack(i))
					stack_button.disabled = game.tile_stacks[i].is_empty()
					context_controls.add_child(stack_button)
			"disperse_source":
				text = "Выберите источник развеивания. Гриб нельзя выбрать после двух развеиваний или под чужой царицей."
				for source in game.dispersal_sources():
					var title: String = "Царица · %d споры" % source["count"] if source["type"] == "queen" else "Гриб %d · %d спор" % [int(source["slot"]) + 1, source["count"]]
					context_controls.add_child(_button(title, func(): _begin_dispersal(source)))
			"choose_wind":
				text = "Грибной бонус: выберите направление ветра без броска."
				for wind in range(3):
					context_controls.add_child(_button("Ветер " + Tri.WIND_NAMES[wind], func(): _choose_wind(wind)))
			"grow":
				text = "Выращивание: выберите карту в руке. Доступная оплата будет найдена внутри одной грибницы."
			"growth_network":
				text = "Есть несколько подходящих грибниц. Выберите вариант оплаты."
				for i in range(growth_options.size()):
					context_controls.add_child(_button(_growth_option_name(growth_options[i], i), func(): _select_growth_option(i)))
			"growth_target":
				text = "Оплата: %s\nТеперь выберите подсвеченный тайл, откуда тратили споры. На тайле не должно быть другого гриба." % _payment_name(growth_option.get("payment", []))
				context_controls.add_child(_button("Другой вариант оплаты", _prepare_growth))
			"decompose":
				text = "Выберите гриб со счётчиком 2. Под чужой царицей разложение заблокировано."
				for slot in game.decomposable_slots():
					context_controls.add_child(_button("Разложить гриб %d" % (slot + 1), func(): _decompose_slot(slot)))
			"develop":
				text = "Развитие: возьмите одну карту рынка или верх колоды во вкладке «Рынок». Пустое место рынка пополнится после хода."
			"insect_queen_target":
				text = "За 2 жетона: выберите чужую царицу."
				for player in game.players:
					if player["id"] != game.current_player:
						context_controls.add_child(_button("Царица: " + player["name"], func(): _select_insect_queen(player["id"])))
			"insect_queen_dest":
				text = "Выберите любой подсвеченный тайл без другой царицы. Это не тратит действие."
			_:
				text = "В свой ход выполните 2 разных действия. Жетоны насекомых можно тратить до/после них."
	if exchange_mode:
		text = "Обмен: выберите ровно 3 карты в руке. Сброс уйдёт под низ колоды, вы получите 1 жетон без траты действия."
		var confirm := _button("Сбросить выбранные (%d/3)" % exchange_selection.size(), _confirm_exchange)
		confirm.disabled = exchange_selection.size() != 3
		context_controls.add_child(confirm)
		context_controls.add_child(_button("Отменить обмен", _toggle_exchange))
	context_instructions.text = text

func _update_board() -> void:
	board.clear_highlights()
	board.selected = selected_tile
	if game.phase == "queens" and not game.current()["is_automa"]:
		board.highlights = game.initial_queen_choices()
	elif not game.dispersal.is_empty():
		board.highlights = game.get_dispersal_choices()
		board.wind_tile = game.dispersal["origin"]
		board.selected = game.dispersal["origin"]
	else:
		match mode:
			"move":
				board.path = move_path.duplicate()
				board.highlights = _move_neighbors()
				if not move_path.is_empty(): board.selected = move_path.back()
			"explore":
				if explore_stack >= 0:
					board.ghosts = game.exploration_choices()
					board.highlights = board.ghosts.duplicate()
			"growth_target": board.highlights.assign(growth_option.get("targets", []))
			"decompose":
				for slot in game.decomposable_slots():
					var coord := game.find_mushroom(game.current_player, slot)
					if coord != Tri.INVALID: board.highlights.append(coord)
			"insect_queen_dest":
				for coord in game.tiles:
					if game.queen_at(coord) == -1: board.highlights.append(coord)
	board.queue_redraw()

func _rebuild_hand() -> void:
	_clear_node(hand_container)
	if game.current()["is_automa"]:
		hand_container.add_child(_label("У автомы нет обычной руки: её параметры задаёт раскрытая карта автомы.", 16))
		return
	if game.phase == "queens":
		for card_id in game.current()["hand"]:
			var hidden := Card.new()
			hidden.face_down = true
			hidden.setup({})
			hidden.disabled = true
			hand_container.add_child(hidden)
		return
	for card_id in game.current()["hand"]:
		var view := Card.new()
		view.setup(game.card(card_id), card_id == selected_card_id or card_id in exchange_selection)
		view.pressed.connect(func(): _on_hand_card(card_id))
		hand_container.add_child(view)
	if game.current()["hand"].is_empty():
		hand_container.add_child(_label("Рука пуста. Выполните «Развитие».", 16))

func _rebuild_market() -> void:
	_clear_node(market_container)
	deck_count_label.text = "Рынок откроется после размещения всех цариц." if game.phase == "queens" else "В колоде: %d · Сброс идёт под низ колоды · Пустые места пополняются после хода" % game.deck.size()
	for i in range(game.market.size()):
		var card_id := str(game.market[i])
		var view := Card.new()
		if game.phase == "queens":
			view.face_down = true
			view.setup({})
			view.disabled = true
		elif card_id.is_empty():
			view.setup({})
			view.disabled = true
		else:
			view.setup(game.card(card_id))
			view.pressed.connect(func(): _on_market_card(i))
		market_container.add_child(view)
	var deck_view := Card.new()
	deck_view.face_down = true
	deck_view.setup({})
	deck_view.disabled = game.phase != "playing" or game.current()["is_automa"] or not game.can_use_action("develop")
	deck_view.pressed.connect(func(): _on_develop_deck())
	market_container.add_child(deck_view)

func _rebuild_slots() -> void:
	_clear_node(slots_container)
	for i in range(game.board_count):
		var slot: Dictionary = game.current()["slots"][i]
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(245, 195)
		slots_container.add_child(panel)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 4)
		panel.add_child(column)
		var heading := _label("ПЛАНШЕТ %d" % (i + 1), 13, Color("#d5bc78"))
		column.add_child(heading)
		if slot["active"].is_empty():
			var empty := _button("Фишка доступна\nРазложено карт: %d" % slot["decomposed"].size(), func(): _on_slot_clicked(i))
			empty.custom_minimum_size.y = 72
			column.add_child(empty)
		else:
			var active := Card.new()
			var definition: Dictionary = game.automa_card(slot["active"]) if game.current()["is_automa"] else game.card(slot["active"])
			active.setup(definition, selected_slot == i, true)
			active.custom_minimum_size.y = 84
			active.pressed.connect(func(): _on_slot_clicked(i))
			column.add_child(active)
		var track := "○ · ·" if slot["active"].is_empty() else ("● " if int(slot["dispersals"]) >= 1 else "○ ") + ("● Готово к разложению" if int(slot["dispersals"]) >= 2 else "○")
		column.add_child(_label(track, 12, Color("#b8c9b4")))
		if game.is_mushroom_blocked(game.current_player, i): column.add_child(_label("Заблокирован чужой царицей", 11, Color("#e18a72")))
		if not slot["decomposed"].is_empty():
			var last_id: String = slot["decomposed"].back()
			var definition: Dictionary = game.automa_card(last_id) if game.current()["is_automa"] else game.card(last_id)
			column.add_child(_label("Под планшетом: %d · %s" % [slot["decomposed"].size(), definition.get("effect_id", "—")], 10, Color("#aebbae")))

func _rebuild_players() -> void:
	_clear_node(players_container)
	for player in game.players:
		var score := game.score_for(player["id"])
		var panel := PanelContainer.new()
		players_container.add_child(panel)
		var text: String = "%s%s   ·   %d очков\nГрибы: %d (%d очк.) · Насекомые: %d (%d очк.) · Жетон конца: +%d\nГрибниц сейчас: %d · Карт в руке: %d" % [
			player["name"], " · ходит" if player["id"] == game.current_player else "", score["total"],
			score["grown_count"], score["mushrooms"], score["insect_count"], score["insects"], score["end_token"],
			game.get_mycelium(player["id"]).size(), player["hand"].size()
		]
		var label := _label(text, 14, game.player_color(player["id"]))
		panel.add_child(label)
	if not game.automa_current_card.is_empty():
		players_container.add_child(_label("Карта автомы: " + game.definition_name(game.automa_current_card, true), 14, Color("#e1c682")))

func _on_action(action: String) -> void:
	if not game.can_use_action(action): return
	_reset_action_mode()
	match action:
		"move": _start_move()
		"explore":
			mode = "explore"
			_set_status("Выберите одну из двух стопок.")
		"disperse":
			mode = "disperse_source"
			_set_status("Выберите царицу или доступный гриб.")
		"grow":
			selected_card_id = ""
			mode = "grow"
			bottom_tabs.current_tab = 0
			_set_status("Выберите карту гриба в руке.")
		"decompose":
			mode = "decompose"
			bottom_tabs.current_tab = 2
			_set_status("Выберите гриб со счётчиком спор 2.")
		"develop":
			mode = "develop"
			bottom_tabs.current_tab = 1
			_set_status("Возьмите карту рынка или верх колоды.")
	refresh()

func _start_move() -> void:
	mode = "move"
	move_path.clear()
	move_path.append(game.current()["queen"])
	_set_status("Стройте путь по одному тайлу; можно вернуться на покинутый тайл.")

func _move_neighbors() -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	if mode != "move" or move_path.is_empty() or move_path.size() > game.max_move_steps(): return result
	var position: Vector3i = move_path.back()
	for coord in Tri.neighbors(position, game.tiles):
		if game.queen_at(coord, game.current_player) == -1: result.append(coord)
	return result

func _finish_move() -> void:
	if move_path.size() < 2: return
	var steps: Array = move_path.slice(1)
	if game.perform_move(steps): _reset_action_mode()
	refresh()

func _select_explore_stack(index: int) -> void:
	explore_stack = index
	_set_status("Теперь выберите призрачный треугольник на краю поля.")
	refresh()

func _begin_dispersal(source: Dictionary) -> void:
	pending_source = source.duplicate()
	if source["type"] == "mushroom" and game.has_bonus("choose_wind", game.current_player, source["slot"]):
		mode = "choose_wind"
	else:
		_start_dispersal_with_wind(-1)

func _choose_wind(wind: int) -> void:
	_start_dispersal_with_wind(wind)

func _start_dispersal_with_wind(wind: int) -> void:
	if game.begin_dispersal(pending_source.get("type", ""), int(pending_source.get("slot", -1)), wind):
		mode = "disperse"
		_set_status("Размещайте споры по одной, начиная с источника.")
	refresh()

func _on_hand_card(card_id: String) -> void:
	if exchange_mode:
		if card_id in exchange_selection: exchange_selection.erase(card_id)
		elif exchange_selection.size() < 3: exchange_selection.append(card_id)
	else:
		selected_card_id = "" if selected_card_id == card_id else card_id
		selected_slot = -1
		if mode == "grow" or mode == "growth_network" or mode == "growth_target":
			growth_card_id = selected_card_id
			_prepare_growth()
	refresh()

func _prepare_growth() -> void:
	if selected_card_id.is_empty():
		mode = "grow"
		return
	growth_card_id = selected_card_id
	growth_options = game.find_growth_options(growth_card_id)
	growth_option.clear()
	if growth_options.is_empty():
		mode = "grow"
		_set_status("Пока нельзя вырастить: нужна свободная фишка и полная цена спор внутри одной грибницы; хотя бы один оплаченный тайл должен быть свободен от гриба.")
	elif growth_options.size() == 1:
		_select_growth_option(0)
	else:
		mode = "growth_network"
		_set_status("Найдено вариантов оплаты: %d." % growth_options.size())

func _growth_option_name(option: Dictionary, index: int) -> String:
	return "Вариант %d · планшет %d · %s" % [index + 1, int(option.get("slot", 0)) + 1, _payment_name(option.get("payment", []))]

func _payment_name(payment: Array) -> String:
	var parts: Array[String] = []
	for resource in payment:
		parts.append("%s (%s)" % [game.color_name(resource["color"]), game.players[resource["owner"]]["name"]])
	return ", ".join(parts)

func _select_growth_option(index: int) -> void:
	if index < 0 or index >= growth_options.size(): return
	growth_option = growth_options[index]
	mode = "growth_target"
	_set_status("Выберите тайл для новой фишки гриба.")
	refresh()

func _decompose_slot(slot: int) -> void:
	if game.perform_decompose(slot):
		_reset_action_mode()
		bottom_tabs.current_tab = 2
	refresh()

func _on_slot_clicked(slot: int) -> void:
	selected_slot = slot
	selected_card_id = ""
	selected_tile = game.find_mushroom(game.current_player, slot)
	if mode == "decompose" and slot in game.decomposable_slots():
		_decompose_slot(slot)
		return
	refresh()

func _on_market_card(index: int) -> void:
	if not game.perform_develop_market(index):
		_set_status("Сейчас нельзя взять эту карту: нужно доступное действие «Развитие».")
	else:
		_reset_action_mode()
	refresh()

func _on_develop_deck() -> void:
	if game.perform_develop_deck():
		if game.pending_development.is_empty(): _reset_action_mode()
	refresh()

func _choose_development(card_id: String) -> void:
	if game.choose_development(card_id): _reset_action_mode()
	refresh()

func _start_insect_move() -> void:
	if game.phase != "playing" or game.current()["is_automa"] or game.current()["insects"] < 2:
		_set_status("Нужно 2 жетона насекомых и обычный ход игрока.")
		refresh()
		return
	_reset_action_mode()
	mode = "insect_queen_target"
	_set_status("Выберите чужую царицу.")
	refresh()

func _select_insect_queen(player_id: int) -> void:
	insect_target = player_id
	mode = "insect_queen_dest"
	_set_status("Теперь выберите любой тайл без царицы.")
	refresh()

func _toggle_exchange() -> void:
	if game.phase != "playing" or game.current()["is_automa"]: return
	exchange_mode = not exchange_mode
	exchange_selection.clear()
	if exchange_mode:
		_reset_action_mode()
		exchange_mode = true
		bottom_tabs.current_tab = 0
		_set_status("Выберите 3 карты для сброса.")
	refresh()

func _confirm_exchange() -> void:
	if game.perform_exchange_cards(exchange_selection.duplicate()):
		exchange_mode = false
		exchange_selection.clear()
	else:
		_set_status("Нужно 3 разные карты и жетон в общем запасе.")
	refresh()

func _on_tile_clicked(coord: Vector3i) -> void:
	selected_tile = coord
	if game.phase == "queens":
		if not game.current()["is_automa"] and game.place_initial_queen(coord):
			_set_status("Царица размещена.")
		refresh()
		_schedule_automa()
		return
	if game.phase != "playing" or game.current()["is_automa"]: return
	if not game.dispersal.is_empty():
		if game.place_dispersal_spore(coord):
			if game.dispersal.is_empty(): _reset_action_mode()
		refresh()
		return
	match mode:
		"move":
			if coord in _move_neighbors():
				move_path.append(coord)
				_set_status("Шагов: %d/%d. Подтвердите путь на панели справа." % [move_path.size() - 1, game.max_move_steps()])
		"explore":
			if explore_stack == -1:
				_set_status("Сначала выберите стопку на панели справа.")
			elif game.perform_explore(explore_stack, coord):
				_reset_action_mode()
		"growth_target":
			if game.perform_growth(growth_card_id, growth_option.get("payment", []), coord, int(growth_option.get("slot", -1))):
				_reset_action_mode()
				bottom_tabs.current_tab = 2
		"decompose":
			for slot in game.decomposable_slots():
				if game.find_mushroom(game.current_player, slot) == coord:
					_decompose_slot(slot)
					break
		"insect_queen_dest":
			if game.perform_insect_move_queen(insect_target, coord): _reset_action_mode()
		_:
			pass
	refresh()

func _end_turn() -> void:
	if game.end_turn():
		_reset_transient()
		refresh()
		_schedule_automa()

func _schedule_automa() -> void:
	if game.players.is_empty() or automa_running or not game.current().get("is_automa", false): return
	if game.phase != "queens" and game.phase != "playing": return
	_run_automa(session_serial)

func _run_automa(serial: int) -> void:
	automa_running = true
	refresh()
	await get_tree().create_timer(0.55).timeout
	if serial != session_serial or game.players.is_empty() or not game.current().get("is_automa", false):
		automa_running = false
		return
	if game.phase == "queens":
		var coord := game.choose_automa_initial_queen()
		if coord != Tri.INVALID: game.place_initial_queen(coord)
	elif game.phase == "playing":
		game.run_automa_turn()
	automa_running = false
	_reset_transient()
	refresh()

func _reset_action_mode() -> void:
	mode = ""
	move_path.clear()
	explore_stack = -1
	growth_options.clear()
	growth_option.clear()
	growth_card_id = ""
	pending_source.clear()
	insect_target = -1

func _reset_transient() -> void:
	_reset_action_mode()
	selected_card_id = ""
	selected_slot = -1
	selected_tile = Tri.INVALID
	exchange_mode = false
	exchange_selection.clear()

func _set_status(text: String) -> void:
	last_message = text
	if is_instance_valid(status_label): status_label.text = text

func _on_game_changed() -> void:
	refresh()

func _on_game_notified(text: String) -> void:
	last_message = text

func _save_game() -> void:
	var error := game.save_game()
	_set_status("Партия сохранена в user://micely_save.json" if error == OK else "Сохранение недоступно сейчас (код %d). Завершите развеивание." % error)
	refresh()

func _load_game() -> void:
	_load_state()

func _load_from_menu() -> void:
	_load_state()

func _load_state() -> void:
	var error := game.load_game()
	if error == OK:
		_build_game_screen(true)
		_set_status("Сохранение загружено.")
		refresh()
		_schedule_automa()
	else:
		if is_instance_valid(status_label): _set_status("Не удалось загрузить сохранение (код %d)." % error)
		else:
			var dialog := AcceptDialog.new()
			dialog.title = "Загрузка"
			dialog.dialog_text = "Сохранение не найдено или повреждено."
			add_child(dialog)
			dialog.popup_centered()

func _show_rules() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Мицелий · краткая памятка"
	dialog.ok_button_text = "Понятно"
	dialog.min_size = Vector2i(820, 620)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.custom_minimum_size = Vector2(790, 580)
	text.text = """[font_size=25][color=#e6ca83]ХОД И ЦЕЛЬ[/color][/font_size]
В свой ход выполните [b]2 разных действия[/b]. Постоянный бонус может разрешить повтор. Игра сразу заканчивается, когда под каждым планшетом игрока лежит хотя бы одна карта.

[b]Перемещение[/b] — царица на 1–2 тайла по сторонам, не через чужие царицы. Насекомое на посещённом тайле сразу ваше. Чужая царица поверх гриба блокирует его развеивание и разложение.
[b]Разведка[/b] — верхний тайл любой стопки ставится стороной к полю.
[b]Развеивание[/b] — царица обычно даёт 2 споры, гриб — число на карте. Первая спора на источнике, вторая за стороной выпавшего ветра, далее по рядам внутри области. Каждый гриб развеивается не более двух раз.
[b]Выращивание[/b] — оплатите указанные цвета спор из одной грибницы. Чёрный тайл универсален. Споры другого владельца доступны на тайле, который контролирует ваша царица или незаблокированный гриб. Новый гриб ставится на один из оплаченных тайлов без другого гриба.
[b]Разложение[/b] — после двух развеиваний уберите гриб с поля, карту под планшет и примените эффект.
[b]Развитие[/b] — возьмите карту рынка или верх колоды. Рынок пополняется после окончания хода.

[color=#e6ca83]НАСЕКОМЫЕ — БЕЗ ДЕЙСТВИЯ[/color]
1 жетон: обновить рынок. 2 жетона: переместить чужую царицу на любой тайл без другой царицы. Сброс 3 карт под низ колоды: получить 1 жетон.

[color=#e6ca83]ПОДСЧЁТ[/color]
Очки всех выращенных грибов (включая разложенные) + 1 очко за каждые полные 2 насекомых + жетон конца. При равенстве: больше выращенных грибов, затем больше насекомых.

[color=#e6ca83]О ПРОТОТИПЕ[/color]
Оплата выращивания выбирается автоматически внутри выбранной грибницы. Карты, распределение насекомых и автома используют демо-данные [b]data/components.json[/b]. Управление полем: колесо — масштаб, перетаскивание — панорама."""
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(790, 580)
	scroll.add_child(text)
	dialog.add_child(scroll)
	add_child(dialog)
	dialog.popup_centered()

func _show_results() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Владыка грибного царства"
	dialog.ok_button_text = "Посмотреть поле"
	var ranking := game.ranking()
	var lines: Array[String] = []
	var place := 0
	var previous_key := ""
	for score in ranking:
		var key := "%s/%s/%s" % [score["total"], score["grown_count"], score["insect_count"]]
		if key != previous_key: place += 1
		lines.append("%d. %s — %d очков\n   Грибы %d · насекомые %d · жетон конца %d" % [place, score["name"], score["total"], score["mushrooms"], score["insects"], score["end_token"]])
		previous_key = key
	var label := _label("\n\n".join(lines), 18, Color("#eee3c7"))
	dialog.add_child(label)
	add_child(dialog)
	dialog.popup_centered(Vector2i(560, 420))

func _label(value: String, font_size: int = 16, color: Color = Color("#e8e5d7")) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.pressed.connect(callback)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return button

## Небольшой фон меню без внешних ресурсов.
class MyceliumMenuArt extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var color := Color(0.55, 0.72, 0.54, 0.09)
		var centers := [Vector2(size.x * 0.12, size.y * 0.2), Vector2(size.x * 0.88, size.y * 0.76)]
		for center in centers:
			for i in range(11):
				var angle := float(i) * TAU / 11.0
				var end: Vector2 = center + Vector2(cos(angle), sin(angle)) * minf(size.x, size.y) * 0.25
				var middle: Vector2 = center.lerp(end, 0.55) + Vector2(sin(angle * 3), cos(angle * 2)) * 30
				draw_polyline(PackedVector2Array([center, middle, end]), color, 2.0, true)
				draw_circle(end, 5, color)
