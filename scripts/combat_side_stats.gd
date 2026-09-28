class_name CombatSideStats
extends RefCounted

var attacks_thrown := 0
var attacks_landed := 0
var blocked_hits := 0
var attacks_evaded := 0
var counter_hits_landed := 0
## Knockdown Meter damage actually applied to the target.
var knockdown_damage_dealt := 0.0
## Knockdowns scored against the opponent this period.
var knockdowns := 0


func duplicate_stats() -> CombatSideStats:
	var copy := CombatSideStats.new()
	copy.attacks_thrown = attacks_thrown
	copy.attacks_landed = attacks_landed
	copy.blocked_hits = blocked_hits
	copy.attacks_evaded = attacks_evaded
	copy.counter_hits_landed = counter_hits_landed
	copy.knockdown_damage_dealt = knockdown_damage_dealt
	copy.knockdowns = knockdowns
	return copy


func add_other(other: CombatSideStats) -> void:
	attacks_thrown += other.attacks_thrown
	attacks_landed += other.attacks_landed
	blocked_hits += other.blocked_hits
	attacks_evaded += other.attacks_evaded
	counter_hits_landed += other.counter_hits_landed
	knockdown_damage_dealt += other.knockdown_damage_dealt
	knockdowns += other.knockdowns


func reset() -> void:
	attacks_thrown = 0
	attacks_landed = 0
	blocked_hits = 0
	attacks_evaded = 0
	counter_hits_landed = 0
	knockdown_damage_dealt = 0.0
	knockdowns = 0
