extends SceneTree

## Title to match page wipe.
## godot --headless --path . -s res://page_transition_smoke_test.gd

const MenuType = preload("res://scripts/title_menu.gd")
const TransitionType = preload("res://scripts/page_transition.gd")
const GameScene = preload("res://scenes/game.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	await _check_direct_game(failures)
	await _check_transition(failures, 0, "NORMAL")
	await _check_transition(failures, 1, "TRAIT")
	_check_panels_do_not_wipe(failures)
	if failures.is_empty():
		print("SMOKE PASS: page transition")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _check_direct_game(failures: Array[String]) -> void:
	var scene := GameScene.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var rounds = scene.get_node("RoundManager")
	if rounds.auto_start != true or rounds.round_state != rounds.RoundState.FIGHTING:
		failures.append("direct game.tscn did not start on its own")
	scene.free()
	await process_frame


func _check_transition(failures: Array[String], mode: int, label: String) -> void:
	for child in root.get_children():
		if child.name == "CombatPrototype":
			child.free()
	var menu: MenuType = MenuType.new()
	root.add_child(menu)
	current_scene = menu
	menu._activate_selected()
	if mode == 1:
		var down := InputEventKey.new()
		down.pressed = true
		down.keycode = KEY_DOWN
		menu._context.handle_key(down)
	var before_accept := 0
	var transition = root.get_node_or_null("PageTransition")
	if transition != null:
		before_accept = transition.accept_count
	var confirm := InputEventKey.new()
	confirm.pressed = true
	confirm.keycode = KEY_ENTER
	menu._context.handle_key(confirm)
	transition = root.get_node_or_null("PageTransition")
	if transition == null or not TransitionType.is_running():
		failures.append("%s confirm did not start a wipe" % label)
		menu.free()
		return
	if transition.accept_count != before_accept + 1:
		failures.append("%s confirm was not exactly one request" % label)
	if transition.handoff_count != before_accept:
		failures.append("%s swapped before the wipe covered the screen" % label)
	if current_scene != menu:
		failures.append("%s removed the title before the cover" % label)
	menu._context.handle_key(confirm)
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	menu._context._on_mode_pressed(mode)
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	menu._unhandled_input(escape)
	if transition.accept_count != before_accept + 1:
		failures.append("%s accepted a repeated confirm" % label)
	if not menu._context.is_open():
		failures.append("%s escape closed the panel during the wipe" % label)
	var saw_title_during_wipe := false
	var saw_cover := false
	var cover_holds := false
	var timer_held := true
	var attacks_held := true
	var stamina_held := true
	var rounds = null
	var stamina_at_cover := -1.0
	for _i in 100:
		await process_frame
		if is_instance_valid(menu) and current_scene == menu and transition.phase == TransitionType.Phase.WIPE_IN:
			saw_title_during_wipe = true
		if transition.handoff_count == before_accept + 1 and transition.phase == TransitionType.Phase.COVERED:
			saw_cover = true
			cover_holds = transition.back_covers_viewport()
			var parent_ok: bool = transition.get_parent() == root
			var title_gone: bool = not is_instance_valid(menu) or menu.is_queued_for_deletion()
			if not parent_ok or not title_gone:
				failures.append("%s wipe was not kept outside the title" % label)
			if current_scene == null or current_scene.name != "CombatPrototype":
				failures.append("%s game scene was not current while covered" % label)
			else:
				var mode_node = current_scene.get_node("GameMode")
				rounds = current_scene.get_node("RoundManager")
				if int(mode_node.mode) != mode:
					failures.append("%s GameMode was not applied before the round" % label)
				if rounds.round_state != rounds.RoundState.IDLE:
					failures.append("%s round started before the wipe revealed the game" % label)
				if current_scene.process_mode != Node.PROCESS_MODE_DISABLED:
					failures.append("%s combat processed while covered" % label)
				stamina_at_cover = current_scene.get_node("PlayerStamina").current_stamina
			if _game_count() != 1:
				failures.append("%s created more than one game scene" % label)
			break
	if not saw_title_during_wipe:
		failures.append("%s title disappeared before the wipe was on screen" % label)
	if not saw_cover:
		failures.append("%s never reached a covered frame" % label)
	elif not cover_holds:
		failures.append("%s dark slab did not cover the viewport" % label)
	var waited := 0.0
	while TransitionType.is_running() and waited < 1.5:
		if rounds != null and is_instance_valid(current_scene):
			if rounds.round_state != rounds.RoundState.IDLE:
				timer_held = false
			var attack = current_scene.get_node("PlayerAttackState")
			var opp = current_scene.get_node("OpponentAttackState")
			if attack.current_state != attack.AttackState.IDLE or opp.current_state != opp.AttackState.IDLE:
				attacks_held = false
			if not is_equal_approx(current_scene.get_node("PlayerStamina").current_stamina, stamina_at_cover):
				stamina_held = false
		await create_timer(0.05).timeout
		waited += 0.05
	if TransitionType.is_running():
		failures.append("%s wipe did not finish" % label)
	if not timer_held:
		failures.append("%s round timer started during wipe-out" % label)
	if not attacks_held:
		failures.append("%s attacks started during wipe-out" % label)
	if not stamina_held:
		failures.append("%s stamina changed during wipe-out" % label)
	if current_scene == null or current_scene.name != "CombatPrototype":
		failures.append("%s did not leave the game scene current" % label)
		return
	var front = transition.get_node_or_null("FrontSlab")
	if front != null and front.visible:
		failures.append("%s left the wipe on screen" % label)
	rounds = current_scene.get_node("RoundManager")
	await process_frame
	if rounds.round_state != rounds.RoundState.FIGHTING:
		failures.append("%s did not enter fighting after the wipe" % label)
	if int(current_scene.get_node("GameMode").mode) != mode:
		failures.append("%s GameMode did not survive the reveal" % label)
	if not rounds.can_accept_combat_input():
		failures.append("%s combat input stayed locked after the wipe" % label)


func _check_panels_do_not_wipe(failures: Array[String]) -> void:
	var menu: MenuType = MenuType.new()
	root.add_child(menu)
	current_scene = menu
	var transition = root.get_node_or_null("PageTransition")
	var accepts := 0
	if transition != null:
		accepts = transition.accept_count
	menu._select_index(1)
	menu._activate_selected()
	var enter := InputEventKey.new()
	enter.pressed = true
	enter.keycode = KEY_ENTER
	menu._context.handle_key(enter)
	menu._select_index(2)
	menu._activate_selected()
	menu._context.handle_key(enter)
	transition = root.get_node_or_null("PageTransition")
	var after := 0
	if transition != null:
		after = transition.accept_count
	if after != accepts or TransitionType.is_running():
		failures.append("tutorial or options started a page wipe")
	menu.free()


func _game_count() -> int:
	var count := 0
	for child in root.get_children():
		if child.name == "CombatPrototype":
			count += 1
	return count
