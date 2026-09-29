class_name MatchSettings
extends Object

## Process-wide presentation settings. One copy survives a scene change.
## BGM and SFX are stored here until an audio bus exists.

enum ScreenShake {
	OFF,
	NORMAL,
	STRONG,
}

enum Difficulty {
	EASY,
	NORMAL,
	HARD,
}

static var bgm_volume := 1.0
static var sfx_volume := 1.0
static var screen_shake := ScreenShake.NORMAL
static var difficulty := Difficulty.NORMAL

const _REACTION_TIME := [1.25, 1.00, 0.75]
const _DEFENSE_CHANCE := [0.80, 1.00, 1.25]
const _OFFENSE_FREQUENCY := [0.75, 1.00, 1.50]
const _RETALIATION_CHANCE := [0.75, 1.00, 1.50]


static func screen_shake_multiplier() -> float:
	match screen_shake:
		ScreenShake.OFF:
			return 0.0
		ScreenShake.STRONG:
			return 1.5
		_:
			return 1.0


static func screen_shake_label() -> String:
	match screen_shake:
		ScreenShake.OFF:
			return "OFF"
		ScreenShake.STRONG:
			return "STRONG"
		_:
			return "NORMAL"


static func step_screen_shake(delta: int) -> void:
	screen_shake = clampi(screen_shake + delta, ScreenShake.OFF, ScreenShake.STRONG)


static func reaction_time_multiplier() -> float:
	return _REACTION_TIME[difficulty]


static func defense_chance_multiplier() -> float:
	return _DEFENSE_CHANCE[difficulty]


static func offense_frequency_multiplier() -> float:
	return _OFFENSE_FREQUENCY[difficulty]


static func retaliation_chance_multiplier() -> float:
	return _RETALIATION_CHANCE[difficulty]


static func scale_chance(base: float, multiplier: float) -> float:
	return clampf(base * multiplier, 0.0, 1.0)


static func step_difficulty(delta: int) -> void:
	difficulty = clampi(difficulty + delta, Difficulty.EASY, Difficulty.HARD)


static func difficulty_name() -> String:
	match difficulty:
		Difficulty.EASY:
			return "EASY"
		Difficulty.HARD:
			return "HARD"
		_:
			return "NORMAL"


static func difficulty_label() -> String:
	match difficulty:
		Difficulty.EASY:
			return "쉬움"
		Difficulty.HARD:
			return "어려움"
		_:
			return "보통"
