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
			{"hook_outgoing_kd": 2.0, "straight_outgoing_kd": 0.5}),
		_make(TraitScript.Id.SHARP_STRAIGHT, "Sharp Straight", "스트레이트 스페셜리스트",
			"Straight KD x2", "Hook KD x0.5", "specialty_punch",
			{"straight_outgoing_kd": 2.0, "hook_outgoing_kd": 0.5}),
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
