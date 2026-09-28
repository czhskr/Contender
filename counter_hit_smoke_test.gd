extends SceneTree

const TraitMath = preload("res://scripts/trait_math.gd")
const MeterType = preload("res://scripts/knockdown_meter.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var normal := TraitMath.taken_kd(10.0, [], 100.0, false, 1.0, false)
	var counter := TraitMath.taken_kd(10.0, [], 100.0, false, 1.0, true)
	var doubled := TraitMath.taken_kd(10.0, [], 100.0, false, 2.0, true)
	var blocked := TraitMath.taken_kd(10.0, [], 100.0, true, 1.0, true)
	if not is_equal_approx(normal, 10.0):
		failures.append("Idle hit should stay 10")
	if not is_equal_approx(counter, 15.0):
		failures.append("Startup or active hit should be 15")
	if not is_equal_approx(doubled, 30.0):
		failures.append("Vulnerability should apply before the counter multiplier")
	if not is_equal_approx(blocked, 2.5):
		failures.append("A block is not a counter hit")
	var meter := MeterType.new()
	meter.max_meter = 300.0
	meter.current_meter = 290.0
	meter.apply_knockdown_damage(counter)
	if not meter.is_full():
		failures.append("A counter hit must still be able to fill the KD meter")
	if failures.is_empty():
		print("SMOKE PASS: counter hit")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)
