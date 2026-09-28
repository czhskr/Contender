extends SceneTree

const HitStunType = preload("res://scripts/hit_stun.gd")


func _initialize() -> void:
	var stun := HitStunType.new()
	stun.apply_hit_stun()
	if stun.is_hit_stunned():
		print("SMOKE FAIL: normal HIT still stuns")
		quit(1)
	else:
		print("SMOKE PASS: hit stun reapply")
		quit(0)
