class_name TraitCatalog
extends RefCounted

const TraitScript = preload("res://scripts/fighter_trait.gd")


static func all_traits() -> Array:
	return [
		_make(TraitScript.Id.IRON_GUARD, "Iron Guard", "철벽",
			"Successful block takes no KD", "Clean hits taken x2", "",
			{"iron_guard": true, "incoming_kd": 2.0}),
		_make(TraitScript.Id.HEAVY_HANDS, "Heavy Hands", "강타자",
			"KD dealt x2", "Attack stamina cost x2", "",
			{"outgoing_kd": 2.0, "attack_cost": 2.0}),
		_make(TraitScript.Id.GLASS_CANNON, "Glass Cannon", "유리대포",
			"KD dealt x2", "KD taken x2", "",
			{"outgoing_kd": 2.0, "incoming_kd": 2.0}),
		_make(TraitScript.Id.ENDURANCE, "Endurance", "지구력",
			"Stamina regen x2", "KD dealt x0.5", "",
			{"stamina_regen": 2.0, "outgoing_kd": 0.5}),
		_make(TraitScript.Id.TOUGH_CHIN, "Tough Chin", "맷집",
			"KD taken x0.5", "Attack stamina cost x1.5", "",
			{"incoming_kd": 0.5, "attack_cost": 1.5}),
		_make(TraitScript.Id.EFFICIENT_STRIKER, "Efficient Striker", "효율적인 타격가",
			"Attack stamina cost x0.5", "KD dealt x0.5", "",
			{"attack_cost": 0.5, "outgoing_kd": 0.5}),
		_make(TraitScript.Id.POWER_HOOKS, "Power Hooks", "훅 스페셜리스트",
			"Hook KD x2", "Straight KD x0.5", "specialty_punch",
			{"hook_outgoing_kd": 2.0, "straight_outgoing_kd": 0.5, "requires_hook_attack": true}),
		_make(TraitScript.Id.SHARP_STRAIGHT, "Sharp Straight", "스트레이트 스페셜리스트",
			"Straight KD x2", "Hook KD x0.5", "specialty_punch",
			{"straight_outgoing_kd": 2.0, "hook_outgoing_kd": 0.5, "requires_straight_attack": true, "requires_hook_attack": true}),
		_make(TraitScript.Id.LAST_STAND, "Last Stand", "최후의 저항",
			"At stamina <= 25, KD dealt x2", "At stamina <= 25, KD taken x2", "",
			{"last_stand": true}),
		_make(TraitScript.Id.QUICK_FEET, "Quick Feet", "빠른 발",
			"Evade window x1.5", "KD taken on block x2", "",
			{"evade_window": 1.5, "slip_duration": 1.5, "block_incoming_kd": 2.0}),
		_make(TraitScript.Id.REFLEX, "Reflex", "반사신경",
			"Evade retrigger x0.5 / reaction x0.5", "Attack stamina cost x1.5", "",
			{"evade_retrigger": 0.5, "reaction_time": 0.5, "attack_cost": 1.5}),
		_make(TraitScript.Id.PRESSURE_FIGHTER, "Pressure Fighter", "압박형",
			"Faster attack links / pressure", "Stamina regen x0.5", "",
			{"attack_link_threshold": 0.5, "offense_pace": 0.5, "stamina_regen": 0.5}),
	]


static func _make(id: int, name_en: String, name_ko: String, positive: String, tradeoff: String, group: String, mods: Dictionary):
	var entry = TraitScript.new()
	entry.id = id
	entry.display_name = "%s / %s" % [name_ko, name_en]
	entry.description = positive
	entry.positive_effect = positive
	entry.tradeoff_description = tradeoff
	entry.exclusive_group = group
	for key in mods.keys():
		entry.set(key, mods[key])
	return entry


static func reveal_name(entry) -> String:
	return str(_reveal(entry)["name"])


static func reveal_benefit(entry) -> String:
	return str(_reveal(entry)["benefit"])


static func reveal_drawback(entry) -> String:
	return str(_reveal(entry)["drawback"])


static func _reveal(entry) -> Dictionary:
	var blank := {"name": "", "benefit": "", "drawback": ""}
	if entry == null:
		return blank
	match int(entry.id):
		TraitScript.Id.IRON_GUARD:
			return {"name": "철벽 가드", "benefit": "가드 방어 강화", "drawback": "받는 피해 증가"}
		TraitScript.Id.HEAVY_HANDS:
			return {"name": "묵직한 주먹", "benefit": "공격력 강화", "drawback": "스태미나 소모 증가"}
		TraitScript.Id.GLASS_CANNON:
			return {"name": "유리 대포", "benefit": "공격력 강화", "drawback": "받는 피해 증가"}
		TraitScript.Id.ENDURANCE:
			return {"name": "지구력", "benefit": "스태미나 회복 강화", "drawback": "공격력 감소"}
		TraitScript.Id.TOUGH_CHIN:
			return {"name": "강한 맷집", "benefit": "받는 피해 감소", "drawback": "스태미나 소모 증가"}
		TraitScript.Id.EFFICIENT_STRIKER:
			return {"name": "효율적인 타격가", "benefit": "스태미나 소모 감소", "drawback": "공격력 감소"}
		TraitScript.Id.POWER_HOOKS:
			return {"name": "훅 스페셜리스트", "benefit": "훅 공격 강화", "drawback": "스트레이트 공격 약화"}
		TraitScript.Id.SHARP_STRAIGHT:
			return {"name": "날카로운 스트레이트", "benefit": "스트레이트 공격 강화", "drawback": "훅 공격 약화"}
		TraitScript.Id.LAST_STAND:
			return {"name": "최후의 저항", "benefit": "저스태미나 공격 강화", "drawback": "저스태미나 받는 피해 증가"}
		TraitScript.Id.QUICK_FEET:
			return {"name": "빠른 발", "benefit": "회피 성능 강화", "drawback": "가드 피해 증가"}
		TraitScript.Id.REFLEX:
			return {"name": "반사신경", "benefit": "연속 회피 강화", "drawback": "스태미나 소모 증가"}
		TraitScript.Id.PRESSURE_FIGHTER:
			return {"name": "압박형 파이터", "benefit": "연속 공격 강화", "drawback": "스태미나 회복 감소"}
		_:
			return blank


class Capabilities:
	var can_use_straight := true
	var can_use_hook := true


static func player_capabilities() -> Capabilities:
	var caps := Capabilities.new()
	caps.can_use_straight = true
	caps.can_use_hook = true
	return caps


static func opponent_capabilities() -> Capabilities:
	var caps := Capabilities.new()
	caps.can_use_straight = true
	## Opponent AI only throws straights. Hook attacks exist as data only.
	caps.can_use_hook = false
	return caps


static func is_trait_eligible(entry, caps: Capabilities) -> bool:
	if entry == null or caps == null:
		return false
	if bool(entry.requires_hook_attack) and not caps.can_use_hook:
		return false
	if bool(entry.requires_straight_attack) and not caps.can_use_straight:
		return false
	return true


static func exclusion_reason(entry, caps: Capabilities) -> String:
	if entry == null or caps == null:
		return ""
	if bool(entry.requires_hook_attack) and not caps.can_use_hook:
		return "requires_hook_attack"
	if bool(entry.requires_straight_attack) and not caps.can_use_straight:
		return "requires_straight_attack"
	return ""


static func eligible_traits(caps: Capabilities) -> Array:
	var pool: Array = []
	for entry in all_traits():
		if is_trait_eligible(entry, caps):
			pool.append(entry)
	return pool


static func english_name(entry) -> String:
	var parts: PackedStringArray = str(entry.display_name).split(" / ")
	return parts[parts.size() - 1]
