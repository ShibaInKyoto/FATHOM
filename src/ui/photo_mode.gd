class_name PhotoMode
extends CanvasLayer
## Photo mode, opened from the pause menu: the dive stays frozen, the HUD
## hides, and the camera pans, zooms and swings round to show the relief of
## the cave walls. Photos are saved like F12 screenshots (see [method shoot]).

signal closed

const PAN_SPEED := 18.0
const ZOOM_SPEED := 22.0
const ORBIT_SPEED := 1.4
const MIN_DISTANCE := 7.0
const MAX_DISTANCE := 70.0
const MAX_YAW := 0.7
const MAX_PITCH := 0.45
const SCREENSHOT_DIR := "user://screenshots"

var _camera: Camera3D
var _saved_transform: Transform3D
var _hidden: Array[CanvasLayer] = []
var _focus := Vector3.ZERO
var _distance := 29.0
var _yaw := 0.0
var _pitch := 0.0
var _dragging := false
var _hint: Label
var _note: Label


## Saves the current frame to the screenshots folder; returns its path.
static func shoot(viewport: Viewport) -> String:
	DirAccess.make_dir_recursive_absolute(SCREENSHOT_DIR)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := SCREENSHOT_DIR.path_join("fathom_%s.png" % stamp)
	viewport.get_texture().get_image().save_png(path)
	return ProjectSettings.globalize_path(path)


func open(camera: Camera3D) -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	_camera = camera
	_saved_transform = camera.transform
	_focus = Vector3(camera.position.x, camera.position.y, 0.0)
	_distance = camera.position.z
	for node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var cl := node as CanvasLayer
		if cl != self and cl.visible and not cl is PostFx:
			cl.visible = false
			_hidden.append(cl)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_hint = UiUtil.label("PHOTO MODE   %s pan   wheel / Q E zoom   right-drag / right stick orbit   " %
		Prompt.key(&"move") + "Enter / F12 take photo   Esc back", &"DimLabel", 18)
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.position.y -= 46.0
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint)
	_note = UiUtil.label("", &"", 18, UiTheme.GOOD)
	_note.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_note.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_note.position.y += 30.0
	add_child(_note)


func _process(delta: float) -> void:
	if _camera == null:
		return
	var pan := Input.get_vector(&"move_left", &"move_right", &"move_down", &"move_up")
	_focus += Vector3(pan.x, pan.y, 0.0) * PAN_SPEED * delta * (_distance / 29.0)
	var orbit := Input.get_vector(&"aim_left", &"aim_right", &"aim_up", &"aim_down")
	_turn(orbit * ORBIT_SPEED * delta)
	var zoom := 0.0
	if Input.is_physical_key_pressed(KEY_Q) or _pad_pressed(JOY_BUTTON_LEFT_SHOULDER):
		zoom += 1.0
	if Input.is_physical_key_pressed(KEY_E) or _pad_pressed(JOY_BUTTON_RIGHT_SHOULDER):
		zoom -= 1.0
	_distance = clampf(_distance - zoom * ZOOM_SPEED * delta, MIN_DISTANCE, MAX_DISTANCE)
	_camera.h_offset = 0.0
	_camera.v_offset = 0.0
	_camera.position = _focus + Basis.from_euler(Vector3(_pitch, _yaw, 0.0)) * Vector3(0.0, 0.0, _distance)
	_camera.look_at(_focus)


func _turn(by: Vector2) -> void:
	_yaw = clampf(_yaw - by.x, -MAX_YAW, MAX_YAW)
	_pitch = clampf(_pitch - by.y, -MAX_PITCH, MAX_PITCH)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_distance = clampf(_distance - 2.0, MIN_DISTANCE, MAX_DISTANCE)
			MOUSE_BUTTON_WHEEL_DOWN:
				_distance = clampf(_distance + 2.0, MIN_DISTANCE, MAX_DISTANCE)
			MOUSE_BUTTON_RIGHT:
				_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		_turn((event as InputEventMouseMotion).relative * 0.005)
	elif event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"screenshot"):
		_take_photo()
	elif event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		_close()
	else:
		return
	get_viewport().set_input_as_handled()


func _take_photo() -> void:
	_hint.visible = false
	_note.visible = false
	await RenderingServer.frame_post_draw
	var path := shoot(get_viewport())
	Audio.play_ui(&"scan_complete")
	_hint.visible = true
	_note.visible = true
	_note.text = "Saved %s" % path


func _close() -> void:
	_camera.transform = _saved_transform
	for cl in _hidden:
		if is_instance_valid(cl):
			cl.visible = true
	closed.emit()
	queue_free()


## Whether [param button] is held on any pad connected.
static func _pad_pressed(button: JoyButton) -> bool:
	for pad in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(pad, button):
			return true
	return false
