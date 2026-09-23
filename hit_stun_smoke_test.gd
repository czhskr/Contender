extends SceneTree

## Hit Stun regression checks (logic-level, no full fight sim).
## Run: godot --headless --path . -s res://hit_stun_smoke_test.gd

const HitStunType = preload("res://scripts/hit_stun.gd")


func _initialize() -> void:
	var failures: Array[String] = []

	_check_component(failures)
	_check_scene(failures)

	if failures.is_empty():
		print("SMOKE PASS: hit stun")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _check_component(failures: Array[String]) -> void:
	var stun := HitStunType.new()
	stun.hit_stun_duration = 0.35
	root.add_child(stun)
	if stun.is_hit_stunned():
		failures.append("HitStun should start inactive")
	stun.apply_hit_stun()
	if not stun.is_hit_stunned():
		failures.append("HitStun apply failed")
	if not is_equal_approx(stun.get_time_remaining(), 0.35):
		failures.append("HitStun duration not 0.35")
	## Refresh should restart full duration.
	stun.apply_hit_stun(0.35)
	if stun.get_time_remaining() < 0.34:
		failures.append("HitStun refresh did not restore duration")
	stun.clear_hit_stun()
	if stun.is_hit_stunned():
		failures.append("HitStun clear failed")
	stun.queue_free()


func _check_scene(failures: Array[String]) -> void:
	var packed: PackedScene = load("res://scenes/game.tscn")
	if packed == null:
		failures.append("game.tscn failed to load")
		return
	var scene := packed.instantiate()
	if scene == null:
		failures.append("game.tscn failed to instantiate")
		return
	if scene.get_node_or_null("PlayerHitStun") == null:
		failures.append("PlayerHitStun missing")
	if scene.get_node_or_null("OpponentHitStun") == null:
		failures.append("OpponentHitStun missing")
	var player_stun = scene.get_node_or_null("PlayerHitStun")
	if player_stun != null and not is_equal_approx(player_stun.hit_stun_duration, 0.35):
		failures.append("PlayerHitStun duration not 0.35")
	var opp_stun = scene.get_node_or_null("OpponentHitStun")
	if opp_stun != null and not is_equal_approx(opp_stun.hit_stun_duration, 0.35):
		failures.append("OpponentHitStun duration not 0.35")
	var player_attack = scene.get_node_or_null("PlayerAttackState")
	if player_attack != null and player_attack.hit_stun == null:
		failures.append("PlayerAttackState.hit_stun not wired")
	var player_action = scene.get_node_or_null("PlayerActionState")
	if player_action != null and player_action.hit_stun == null:
		failures.append("PlayerActionState.hit_stun not wired")
	var opp_ai = scene.get_node_or_null("OpponentAI")
	if opp_ai != null and opp_ai.opponent_hit_stun == null:
		failures.append("OpponentAI.opponent_hit_stun not wired")
	## Hit reaction path: combat prototype applies stun only on HIT.
	var proto = scene
	if not proto.has_method("_apply_player_hit_reaction"):
		failures.append("Missing _apply_player_hit_reaction")
	if not proto.has_method("_apply_opponent_hit_reaction"):
		failures.append("Missing _apply_opponent_hit_reaction")
	scene.free()
