extends Node
## Scene transitions with a fade to black.

const SPLASH := "res://src/ui/splash/studio_splash.tscn"
const TITLE := "res://src/ui/title/title_screen.tscn"
const HANGAR := "res://src/ui/hangar/hangar.tscn"
const DIVE := "res://src/dive/dive.tscn"
const ENDING := "res://src/ui/ending/ending.tscn"

var _layer: CanvasLayer
var _fade: ColorRect
var _note: Label
var _busy := false
var _quitting := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.0, 0.01, 0.02, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_fade)
	_note = UiUtil.label("", &"DimLabel", 18)
	_note.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_note.position += Vector2(24.0, -40.0)
	_layer.add_child(_note)
	_setup_capture()


## Debug capture: `-- --capture=<dir> --capture-at=2,5,8` saves screenshots at
## those times (seconds since boot) and quits after the last one.
func _setup_capture() -> void:
	var dir := ""
	var times := PackedFloat32Array()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture="):
			dir = a.split("=", true, 1)[1]
		elif a.begins_with("--capture-at="):
			for t in a.split("=", true, 1)[1].split(","):
				times.append(float(t))
	if dir == "" or times.is_empty():
		return
	for i in times.size():
		var path := dir.path_join("capture_%02d.png" % i)
		var last := i == times.size() - 1
		get_tree().create_timer(times[i], true, false, true).timeout.connect(func() -> void:
			get_viewport().get_texture().get_image().save_png(path)
			if last:
				quit())


## Quits cleanly: silences audio and gives the audio server a few frames to
## release its playbacks before the engine shuts down.
func quit(exit_code := 0) -> void:
	if _quitting:
		return
	_quitting = true
	Audio.stop_all()
	for i in 3:
		await get_tree().process_frame
	get_tree().quit(exit_code)


## F11 toggles fullscreen and F12 saves a screenshot, anywhere in the game.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"fullscreen"):
		Settings.toggle_fullscreen()
	elif event.is_action_pressed(&"screenshot"):
		var path := PhotoMode.shoot(get_viewport())
		_note.text = "Screenshot saved: %s" % path
		_note.modulate.a = 1.0
		create_tween().tween_property(_note, ^"modulate:a", 0.0, 1.0).set_delay(2.5)
		get_viewport().set_input_as_handled()


## True while a transition is fading; [method go_to] calls are ignored then.
func is_busy() -> bool:
	return _busy


func go_to(path: String, fade_time := 0.6) -> void:
	if _busy:
		return
	_busy = true
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween()
	tween.tween_property(_fade, ^"color:a", 1.0, fade_time)
	await tween.finished
	get_tree().paused = false
	get_tree().change_scene_to_file(path)
	# Let the new scene build (and any generation spikes settle) before fading in.
	await get_tree().process_frame
	await get_tree().process_frame
	var back := create_tween()
	back.tween_property(_fade, ^"color:a", 0.0, fade_time)
	await back.finished
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false


## Fades the screen to black and back while [param work] runs in between.
func fade_through(work: Callable, fade_time := 0.5) -> void:
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween()
	tween.tween_property(_fade, ^"color:a", 1.0, fade_time)
	await tween.finished
	await work.call()
	var back := create_tween()
	back.tween_property(_fade, ^"color:a", 0.0, fade_time)
	await back.finished
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
