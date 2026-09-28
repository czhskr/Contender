class_name OpponentDifficultySettings
extends Resource

## Behavioral difficulty preset (not HP/damage scaling).

@export_group("Identity")
@export var display_name := "Normal"

@export_group("Reaction")
## Delay after player attack Startup before AI may defend.
@export_range(0.05, 2.0, 0.01, "or_greater") var reaction_delay := 0.16
@export_range(0.0, 1.0, 0.01) var reaction_delay_variance := 0.08

@export_group("Offense Timing")
@export_range(0.0, 10.0, 0.01, "or_greater") var attack_interval_min := 0.1
@export_range(0.0, 10.0, 0.01, "or_greater") var attack_interval_max := 0.3
@export_range(0.0, 1.0, 0.01) var aggression := 0.62

@export_group("Follow-up Pressure")
@export_range(0.0, 1.0, 0.01) var follow_up_chance := 0.6
@export_range(0.0, 2.0, 0.01, "or_greater") var follow_up_delay_min := 0.05
@export_range(0.0, 2.0, 0.01, "or_greater") var follow_up_delay_max := 0.12

@export_group("Defense")
@export_range(0.0, 1.0, 0.01) var defensive_reaction_chance := 0.5
@export_range(0.0, 1.0, 0.01) var evade_chance := 0.35
@export_range(0.0, 1.0, 0.01) var guard_chance := 0.35
@export_range(0.0, 1.0, 0.01) var mistake_chance := 0.2

@export_group("Attack Preference")
@export_range(0.0, 10.0, 0.05, "or_greater") var straight_weight := 1.0
## Kept for future Hook re-enable. Current AI filters Hooks out of candidates.
@export_range(0.0, 10.0, 0.05, "or_greater") var hook_weight := 0.85

@export_group("Stamina Behavior")
@export_range(0.0, 1000.0, 0.5, "or_greater") var low_stamina_threshold := 25.0
@export_range(0.0, 1.0, 0.01) var low_stamina_wait_chance := 0.35
