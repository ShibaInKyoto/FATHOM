extends Node
## Player preferences (persisted to user://settings.cfg) and the input map.
##
## Input actions are registered in code rather than in project.godot so the
## defaults live next to the code that reads them.

signal changed

enum Quality { LOW, MEDIUM, HIGH, ULTRA }

const PATH := "user://settings.cfg"
## A binding with this device answers every pad, keyboard and mouse.
const ALL_DEVICES := -1
const QUALITY_NAMES: PackedStringArray = ["Low", "Medium", "High", "Ultra"]
## Per preset: the share of the screen's resolution the 3D view renders at,
## and the most rows of pixels it renders. Up to that height a screen gets
## the preset's own scale (so a 1080p or 1440p screen looks as it always
## has); above it, as on a 4K screen, the 3D view renders at that height and
## FSR sharpens it up to the screen, with the menus and HUD still drawn at
## full resolution. A 4K screen has four times the pixels of a 1080p one, and
## the lighting, fog and post effects cost per pixel.
const RENDER_SCALE: Array[float] = [0.67, 0.85, 1.0, 1.0]
const RENDER_HEIGHT: Array[int] = [900, 1080, 1440, 1800]
## Actions whose primary keyboard or mouse binding the player can change.
## Gamepad bindings, the arrow keys and pause stay fixed.
const REBINDABLE: Array[StringName] = [&"move_up", &"move_left", &"move_down", &"move_right", &"fire", &"tool",
	&"cycle_tool", &"ping", &"boost", &"lamp", &"map"]

var master_volume := 0.8
var music_volume := 0.65
var sfx_volume := 0.9
var quality := Quality.HIGH
var fullscreen := true
var vsync := true
var screen_shake := 1.0
var show_fps := false
## Assist mode: the submarine takes much less damage and timing windows widen.
var assist := false
## Gamepad rumble on impacts.
var rumble := true
## Accessibility: show where threat sounds come from (see [SoundCues]).
var sound_cues := false
## Accessibility: softer, slower bursts of light and no rippling glows.
var reduce_flashing := false
## Set once [QualityProbe] has checked this machine's frame rate.
var quality_probed := false
## Last input device used; prompts and aiming adapt to it.
var using_gamepad := false
## The player's rebinds: action -> {"key": physical keycode} or {"mouse": button}.
var bindings: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_inputs()
	load_settings()
	apply()
	get_tree().root.size_changed.connect(_apply_render_scale)


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.4):
		using_gamepad = true
	elif event is InputEventMouseMotion or event is InputEventKey or event is InputEventMouseButton:
		using_gamepad = false


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	master_volume = cfg.get_value("audio", "master", master_volume)
	music_volume = cfg.get_value("audio", "music", music_volume)
	sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
	quality = clampi(cfg.get_value("video", "quality", quality), Quality.LOW, Quality.ULTRA) as Quality
	fullscreen = cfg.get_value("video", "fullscreen", fullscreen)
	vsync = cfg.get_value("video", "vsync", vsync)
	show_fps = cfg.get_value("video", "show_fps", show_fps)
	quality_probed = cfg.get_value("video", "quality_probed", quality_probed)
	screen_shake = cfg.get_value("game", "screen_shake", screen_shake)
	assist = cfg.get_value("game", "assist", assist)
	rumble = cfg.get_value("game", "rumble", rumble)
	sound_cues = cfg.get_value("game", "sound_cues", sound_cues)
	reduce_flashing = cfg.get_value("game", "reduce_flashing", reduce_flashing)
	var saved: Variant = cfg.get_value("input", "bindings", {})
	bindings = saved if saved is Dictionary else {}
	_apply_bindings()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("video", "quality", quality)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "show_fps", show_fps)
	cfg.set_value("video", "quality_probed", quality_probed)
	cfg.set_value("game", "screen_shake", screen_shake)
	cfg.set_value("game", "assist", assist)
	cfg.set_value("game", "rumble", rumble)
	cfg.set_value("game", "sound_cues", sound_cues)
	cfg.set_value("game", "reduce_flashing", reduce_flashing)
	cfg.set_value("input", "bindings", bindings)
	cfg.save(PATH)


## Applies window and viewport settings and notifies listeners (audio buses,
## level environments) so they can apply theirs.
func apply() -> void:
	if not DisplayServer.get_name() == "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var vp := get_viewport()
	match quality:
		Quality.LOW, Quality.MEDIUM:
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		Quality.HIGH:
			vp.msaa_3d = Viewport.MSAA_2X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		Quality.ULTRA:
			vp.msaa_3d = Viewport.MSAA_4X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_apply_render_scale()
	changed.emit()


## The 3D view's resolution for the preset and the window's size (see
## [constant RENDER_HEIGHT]); upscaled with FSR when below the screen's.
func _apply_render_scale() -> void:
	var vp := get_viewport()
	var scale := render_scale(quality, vp.size.y)
	vp.scaling_3d_scale = scale
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if scale < 0.999 else Viewport.SCALING_3D_MODE_BILINEAR


## The share of a screen [param rows] pixels tall that preset [param q]
## renders the 3D view at.
static func render_scale(q: Quality, rows: int) -> float:
	return minf(RENDER_SCALE[q], RENDER_HEIGHT[q] / maxf(float(rows), 1.0))


## Damage multiplier applied to the player's submarine.
func damage_taken_mult() -> float:
	return 0.6 if assist else 1.0


## Scale for rhythm timing windows (the Choir's waves).
func timing_window_mult() -> float:
	return 1.6 if assist else 1.0


## Short gamepad rumble scaled by [param strength] (0..1).
func rumble_pulse(strength: float, duration := 0.2) -> void:
	if rumble and using_gamepad:
		for pad in Input.get_connected_joypads():
			Input.start_joy_vibration(pad, clampf(strength, 0.0, 1.0) * 0.6, clampf(strength, 0.0, 1.0), duration)


func toggle_fullscreen() -> void:
	fullscreen = not fullscreen
	apply()
	save_settings()


# --- Input map ---------------------------------------------------------------

## The default events of every action, in priority order: the first key or
## mouse button is an action's primary (rebindable) binding.
static func default_inputs() -> Dictionary[StringName, Array]:
	return {
		&"move_left": [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)],
		&"move_right": [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)],
		&"move_up": [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)],
		&"move_down": [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)],
		&"aim_left": [_axis(JOY_AXIS_RIGHT_X, -1.0)],
		&"aim_right": [_axis(JOY_AXIS_RIGHT_X, 1.0)],
		&"aim_up": [_axis(JOY_AXIS_RIGHT_Y, -1.0)],
		&"aim_down": [_axis(JOY_AXIS_RIGHT_Y, 1.0)],
		&"fire": [_mouse(MOUSE_BUTTON_LEFT), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)],
		&"tool": [_mouse(MOUSE_BUTTON_RIGHT), _joy(JOY_BUTTON_RIGHT_SHOULDER)],
		&"cycle_tool": [_key(KEY_Q), _joy(JOY_BUTTON_LEFT_SHOULDER)],
		&"ping": [_key(KEY_SPACE), _joy(JOY_BUTTON_A)],
		&"boost": [_key(KEY_SHIFT), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)],
		&"lamp": [_key(KEY_F), _joy(JOY_BUTTON_Y)],
		&"map": [_key(KEY_TAB), _joy(JOY_BUTTON_BACK)],
		&"pause": [_key(KEY_ESCAPE), _key(KEY_P), _joy(JOY_BUTTON_START)],
		&"fullscreen": [_key(KEY_F11)],
		&"screenshot": [_key(KEY_F12)],
		&"pick_1": [_key(KEY_1)],
		&"pick_2": [_key(KEY_2)],
		&"pick_3": [_key(KEY_3)],
		# Stepping through a menu's tabs (the hangar's): the bumpers, or Q and E.
		&"ui_tab_prev": [_key(KEY_Q), _joy(JOY_BUTTON_LEFT_SHOULDER)],
		&"ui_tab_next": [_key(KEY_E), _joy(JOY_BUTTON_RIGHT_SHOULDER)],
	}


func _register_inputs() -> void:
	var defaults := default_inputs()
	for action in defaults:
		_set_events(action, defaults[action])
	# Godot's menu actions only know the keyboard (and the d-pad for moving
	# focus): A presses the focused button, B backs out.
	for pair: Array in [[&"ui_accept", JOY_BUTTON_A], [&"ui_cancel", JOY_BUTTON_B]]:
		var e := _joy(pair[1])
		if not InputMap.action_has_event(pair[0], e):
			InputMap.action_add_event(pair[0], e)
	_any_pad()


## Every gamepad binding, Godot's own menu actions' included, answers any
## pad. An event made in code belongs to device 0 alone, and the system may
## number the player's pad 1 or higher (a second controller, a virtual one
## from Steam Input, a wheel or a drawing tablet plugged in first): then not
## one action would answer it.
func _any_pad() -> void:
	for action in InputMap.get_actions():
		for e in InputMap.action_get_events(action):
			if (e is InputEventJoypadButton or e is InputEventJoypadMotion) and e.device != ALL_DEVICES:
				InputMap.action_erase_event(action, e)
				e.device = ALL_DEVICES
				InputMap.action_add_event(action, e)


func _set_events(action: StringName, events: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)
	InputMap.action_erase_events(action)
	for e: InputEvent in events:
		InputMap.action_add_event(action, e)


## The action's primary keyboard or mouse event: the one the player can rebind.
func primary_event(action: StringName) -> InputEvent:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey or e is InputEventMouseButton:
			return e
	return null


## Readable name of an action's primary binding, in the player's keyboard layout.
func binding_name(action: StringName) -> String:
	return event_name(primary_event(action))


## Makes [param event] (a key or mouse button) the primary binding of
## [param action]. Another action that was using it takes over the old one,
## so nothing is ever left unbound.
func rebind(action: StringName, event: InputEvent) -> void:
	var wanted := _decode(_encode(event))
	if wanted == null or not REBINDABLE.has(action):
		return
	var old := primary_event(action)
	for other in REBINDABLE:
		if other != action and _same(primary_event(other), wanted) and old:
			_set_primary(other, old)
			bindings[String(other)] = _encode(old)
	_set_primary(action, wanted)
	bindings[String(action)] = _encode(wanted)
	save_settings()


func reset_bindings() -> void:
	bindings.clear()
	var defaults := default_inputs()
	for action in REBINDABLE:
		_set_events(action, defaults[action])
	save_settings()


func _set_primary(action: StringName, event: InputEvent) -> void:
	var events := InputMap.action_get_events(action)
	var replaced := false
	for i in events.size():
		if events[i] is InputEventKey or events[i] is InputEventMouseButton:
			events[i] = event
			replaced = true
			break
	if not replaced:
		events.push_front(event)
	_set_events(action, events)


func _apply_bindings() -> void:
	for key: Variant in bindings.keys():
		var action := StringName(str(key))
		var event := _decode(bindings[key])
		if REBINDABLE.has(action) and event:
			_set_primary(action, event)
		else:
			bindings.erase(key)


static func _encode(e: InputEvent) -> Dictionary:
	if e is InputEventKey:
		var k := e as InputEventKey
		return {"key": int(k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode)}
	if e is InputEventMouseButton:
		return {"mouse": int((e as InputEventMouseButton).button_index)}
	return {}


static func _decode(d: Variant) -> InputEvent:
	if not d is Dictionary:
		return null
	if d.has("key") and int(d.key) != KEY_NONE:
		return _key(int(d.key) as Key)
	if d.has("mouse") and int(d.mouse) > 0:
		return _mouse(int(d.mouse) as MouseButton)
	return null


static func _same(a: InputEvent, b: InputEvent) -> bool:
	return a != null and b != null and _encode(a) == _encode(b)


## A readable name for a key or mouse button, in the player's keyboard layout
## (the physical W key reads "Z" on an AZERTY keyboard).
static func event_name(e: InputEvent) -> String:
	if e is InputEventKey:
		var physical := (e as InputEventKey).physical_keycode
		# The headless server (tests, CI) has no keyboard layout to ask.
		var code := physical
		if DisplayServer.get_name() != "headless":
			code = DisplayServer.keyboard_get_keycode_from_physical(physical)
		return OS.get_keycode_string(code if code != KEY_NONE else physical)
	if e is InputEventMouseButton:
		match (e as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT:
				return "LMB"
			MOUSE_BUTTON_RIGHT:
				return "RMB"
			MOUSE_BUTTON_MIDDLE:
				return "MMB"
		return "Mouse %d" % (e as InputEventMouseButton).button_index
	return "-"


static func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.device = ALL_DEVICES
	return e


static func _mouse(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.device = ALL_DEVICES
	return e


static func _joy(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.device = ALL_DEVICES
	return e


static func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	e.device = ALL_DEVICES
	return e
