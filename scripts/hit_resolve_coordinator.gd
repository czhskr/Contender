class_name HitResolveCoordinator
extends Node

## Batches same-frame Active hit resolution so tree/signal order cannot
## cancel one side before the other already-Active attack resolves.
## Startup interrupt (Active vs non-Active) still uses normal resolve+cancel.

const AttackStateType = preload("res://scripts/player_attack_state.gd")
const OpponentAttackStateType = preload("res://scripts/opponent_attack_state.gd")

@export var offense_resolver: Node
@export var defense_resolver: Node
@export var player_attack_state: AttackStateType
@export var opponent_attack_state: OpponentAttackStateType

@export_group("Debug")
@export var print_trade_debug := false

var _pending_player_attack := -1
var _pending_opponent_data = null
var _flush_scheduled := false


func queue_player_active(attack: int) -> void:
	_pending_player_attack = attack
	_schedule_flush()


func queue_opponent_active(attack_data) -> void:
	_pending_opponent_data = attack_data
	_schedule_flush()


func _schedule_flush() -> void:
	if _flush_scheduled:
		return
	_flush_scheduled = true
	call_deferred("_flush")


func _flush_pending_opponent_defense() -> void:
	var ai: Node = get_parent().get_node_or_null("OpponentAI") if get_parent() != null else null
	if ai != null and ai.has_method("resolve_pending_defense_now"):
		ai.resolve_pending_defense_now()


func _flush() -> void:
	_flush_scheduled = false
	var player_attack := _pending_player_attack
	var opponent_data = _pending_opponent_data
	_pending_player_attack = -1
	_pending_opponent_data = null

	var is_trade := player_attack >= 0 and opponent_data != null
	if print_trade_debug and is_trade:
		print("[HitResolve] simultaneous Active trade")

	## Resolve damages first (both, if trade). Cancels happen via combat reactions
	## after each emit; queued attack_data means opponent resolve does not need
	## the attack state to still be ACTIVE.
	if player_attack >= 0 and offense_resolver != null:
		_flush_pending_opponent_defense()
		offense_resolver.resolve_hit_now(player_attack)
	if opponent_data != null and defense_resolver != null:
		defense_resolver.resolve_attack(opponent_data)
