class_name CursorPolicy
extends Object

## One place that shows or hides the custom mouse cursor.


static func show_pointer() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


static func hide_pointer() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
