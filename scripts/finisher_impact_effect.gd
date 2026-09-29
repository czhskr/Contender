class_name FinisherImpactEffect
extends CanvasLayer

## Brief white flash at finisher start (wall-clock). No lingering dark overlay.
## Uses Time.get_ticks_msec; independent of combat freeze / time_scale.

@export_group("Flash")
@export_range(0.0, 1.0, 0.01) var flash_peak_alpha := 0.82
@export_range(0.02, 0.5, 0.01, "or_greater") var flash_duration := 0.12

var _flash: ColorRect
var _playing := false
var _start_msec := 0
var _token := 0


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	_build_nodes()
	visible = false


func _build_nodes() -> void:
	_flash = ColorRect.new()
	_flash.name = "ImpactFlash"
	_flash.color = Color(1.0, 1.0, 1.0, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_flash)


func play_finisher(_freeze_duration: float) -> void:
	## freeze_duration ignored for overlay hold — only flash plays, then clear.
	_token += 1
	_playing = true
	_start_msec = Time.get_ticks_msec()
	visible = true
	_flash.color = Color(1.0, 1.0, 1.0, 0.0)
	set_process(true)


func stop_immediate() -> void:
	_token += 1
	_playing = false
	set_process(false)
	_flash.color = Color(1.0, 1.0, 1.0, 0.0)
	visible = false


func _process(_delta: float) -> void:
	if not _playing:
		set_process(false)
		return

	var elapsed := float(Time.get_ticks_msec() - _start_msec) / 1000.0

	## Flash: 0 → peak → 0 over flash_duration, then fully clear.
	var flash_a := 0.0
	if flash_duration > 0.0 and elapsed < flash_duration:
		var t := elapsed / flash_duration
		if t < 0.35:
			flash_a = flash_peak_alpha * (t / 0.35)
		else:
			flash_a = flash_peak_alpha * (1.0 - (t - 0.35) / 0.65)
		_flash.color = Color(1.0, 1.0, 1.0, clampf(flash_a, 0.0, 1.0))
		return

	## Flash done — show original scene for the rest of the freeze.
	_flash.color = Color(1.0, 1.0, 1.0, 0.0)
	_playing = false
	set_process(false)
	visible = false


func _exit_tree() -> void:
	stop_immediate()
