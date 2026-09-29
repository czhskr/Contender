extends SceneTree

const Catalog = preload("res://scripts/trait_catalog.gd")
const MathType = preload("res://scripts/trait_math.gd")
const Vuln = preload("res://scripts/knockdown_vulnerability.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	_check_baseline(failures)
	_check_caps(failures)
	_check_once(failures)
	_print_named()
	_print_pairs()
	if failures.is_empty():
		print("SMOKE PASS: trait modifier stack")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _check_baseline(failures: Array[String]) -> void:
	var row: Dictionary = MathType.compose_kd(10.0, 1, [], 100.0, [], 100.0, false, 1.0, false)
	if not is_equal_approx(row["final"], 10.0):
		failures.append("No-trait straight should stay 10")
	row = MathType.compose_kd(10.0, 1, [], 100.0, [], 100.0, false, 1.0, true)
	if not is_equal_approx(row["final"], 15.0) or not is_equal_approx(row["counter"], 1.5):
		failures.append("Counter should be exactly x1.5 once")
	row = MathType.compose_kd(10.0, 1, [], 100.0, [], 100.0, true, 1.0, true)
	if not is_equal_approx(row["final"], 2.5):
		failures.append("Block should stay 2.5 without Iron Guard")


func _check_caps(failures: Array[String]) -> void:
	var heavy = _find("Heavy Hands")
	var sharp = _find("Sharp Straight")
	var row: Dictionary = MathType.compose_kd(10.0, 1, [heavy, sharp], 100.0, [], 100.0, false, 1.0, true)
	if row["offensive_trait"] > 2.5:
		failures.append("Offensive traits exceeded x2.5")
	if not is_equal_approx(row["final"], 37.5):
		failures.append("Heavy+Sharp counter at full stamina should be 37.5, got %.2f" % row["final"])
	var glass = _find("Glass Cannon")
	row = MathType.compose_kd(10.0, 1, [heavy, sharp], 100.0, [glass], 100.0, false, 1.0, true)
	if row["trait_component"] > 3.0:
		failures.append("Combined trait contribution exceeded x3")
	if not is_equal_approx(row["final"], 45.0):
		failures.append("Attacker stack vs Glass Cannon counter should be 45, got %.2f" % row["final"])
	var iron = _find("Iron Guard")
	row = MathType.compose_kd(10.0, 1, [heavy], 100.0, [iron], 100.0, true, 1.0, true)
	if not is_equal_approx(row["final"], 0.0) or row["block_source"] != "Iron Guard":
		failures.append("Iron Guard block should be 0 and named")


func _check_once(failures: Array[String]) -> void:
	var heavy = _find("Heavy Hands")
	var row: Dictionary = MathType.compose_kd(10.0, 1, [heavy], 100.0, [], 100.0, false, 1.03, true)
	if not is_equal_approx(row["offensive_trait"], 2.0):
		failures.append("Heavy Hands applied more than once")
	if not is_equal_approx(row["stamina_vulnerability"], 1.03):
		failures.append("Stamina vulnerability was rewritten")
	if not is_equal_approx(row["final"], 30.9):
		failures.append("Single Heavy Hands counter at 75 stamina should be 30.9, got %.2f" % row["final"])


func _print_named() -> void:
	var vuln := Vuln.new().multiplier_for(75.0, 100.0)
	print("OLD Heavy Hands + Sharp Straight counter at 75 stamina = %.2f" % (10.0 * 2.0 * 2.0 * vuln * 1.5))
	var row: Dictionary = MathType.compose_kd(10.0, 1, [_find("Heavy Hands"), _find("Sharp Straight")], 75.0, [], 75.0, false, vuln, true)
	print("NEW Heavy Hands + Sharp Straight counter = %.2f trait=%.2f" % [row["final"], row["trait_component"]])


func _print_pairs() -> void:
	var traits: Array = Catalog.all_traits()
	var rows: Array = []
	for i in traits.size():
		for j in range(i + 1, traits.size()):
			var first = traits[i]
			var second = traits[j]
			if first.exclusive_group != "" and first.exclusive_group == second.exclusive_group:
				continue
			var pair := [first, second]
			var straight: Dictionary = MathType.compose_kd(10.0, 1, pair, 100.0, [], 100.0, false, 1.0, true)
			var hook: Dictionary = MathType.compose_kd(15.0, 3, pair, 100.0, [], 100.0, false, 1.0, true)
			rows.append({
				"name": "%s + %s" % [first.display_name, second.display_name],
				"straight": straight["final"],
				"hook": hook["final"],
			})
	rows.sort_custom(func(a, b): return a["straight"] > b["straight"])
	print("TOP STRAIGHT COUNTER PAIRS")
	for index in mini(10, rows.size()):
		var row: Dictionary = rows[index]
		print("%d. %.2f straight / %.2f hook | %s" % [index + 1, row["straight"], row["hook"], row["name"]])


func _find(name_part: String):
	for entry in Catalog.all_traits():
		if String(entry.display_name).contains(name_part):
			return entry
	return null
