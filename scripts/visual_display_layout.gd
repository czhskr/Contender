class_name VisualDisplayLayout
extends RefCounted

## Separate Player / Opponent display math.
## Viewport: 1152x648 (16:9).

const VIEWPORT_SIZE := Vector2(1152, 648)

## Player full-frame POV canvas (16:9). Scale 0.75 maps exactly onto the viewport.
const PLAYER_SOURCE_CANVAS_SIZE := Vector2(1536, 864)
## 1152/1536 = 648/864 = 0.75
const DEFAULT_PLAYER_DISPLAY_SCALE := 0.75

## Opponent authored canvas (separate from Player).
const OPPONENT_SOURCE_CANVAS_SIZE := Vector2(1536, 1024)
## Contain fit (height-limited): 648/1024 ≈ 0.6328125
const DEFAULT_OPPONENT_DISPLAY_SCALE := 648.0 / 1024.0


static func compute_player_full_frame_scale() -> float:
	## Both axes agree for 1536x864 → 1152x648.
	return VIEWPORT_SIZE.x / PLAYER_SOURCE_CANVAS_SIZE.x


static func compute_opponent_contain_scale() -> float:
	return minf(
		VIEWPORT_SIZE.x / OPPONENT_SOURCE_CANVAS_SIZE.x,
		VIEWPORT_SIZE.y / OPPONENT_SOURCE_CANVAS_SIZE.y
	)


## Player full-frame: source (0,0) maps to viewport (0,0).
static func compute_player_base_position() -> Vector2:
	return Vector2.ZERO


## Opponent: bottom-aligned; center horizontally when letterboxed.
static func compute_opponent_base_position(display_scale: float) -> Vector2:
	var scaled := OPPONENT_SOURCE_CANVAS_SIZE * display_scale
	return Vector2(
		(VIEWPORT_SIZE.x - scaled.x) * 0.5,
		VIEWPORT_SIZE.y - scaled.y
	)
