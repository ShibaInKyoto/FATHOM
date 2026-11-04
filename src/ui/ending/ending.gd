extends Node3D
## Victory: the long climb back to the light, an epilogue and the credits.

const LINES: PackedStringArray = [
	"The song did not end. It changed.",
	"For the first time in longer than there have been words, something at the bottom of the world is listening.",
	"The trench holds still behind you as you rise.",
	"Somewhere below, a beacon keeps pinging - slower now, almost patient. Waiting for the next voice to answer.",
]

## Shown only to pilots who recovered every Meridian log: what became of the crew.
const RECORD_LINES: PackedStringArray = [
	"Hale and Sato's pod was never found. Neither was Vasquez's drone.",
	"But woven through the last song were four human voices, and one of them was humming a lullaby.",
	"Okafor stayed to listen. She is listening still. And now, so is it.",
]

var _column: VBoxContainer
## Set once the player presses something: the rest of the epilogue appears at once.
var _fast := false
var _tween: Tween


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var backdrop := MenuBackdrop.new()
	backdrop.force_zone = 0
	# Keep the sub off to the side of the centred epilogue text.
	backdrop.view_shift = -19.0
	add_child(backdrop)
	Audio.play_music(&"ending", 3.0)
	var layer := CanvasLayer.new()
	add_child(layer)
	var ui := Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.theme = UiTheme.get_theme()
	layer.add_child(ui)
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.02, 0.04, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(center)
	_column = VBoxContainer.new()
	_column.custom_minimum_size = Vector2(1100, 0)
	_column.add_theme_constant_override(&"separation", 18)
	center.add_child(_column)
	_sequence()
	if Autopilot.requested():
		print("AUTOPILOT: run over outcome=VICTORY banked=%d score=%d" % [Game.last_victory_banked, Game.last_score])
		get_tree().create_timer(3.0).timeout.connect(Router.quit)


func _sequence() -> void:
	var title := UiUtil.label("THE CHOIR IS LISTENING", &"TitleLabel", 76, UiTheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	await _reveal(title, 1.5)
	for line in LINES:
		var l := UiUtil.label(line, &"", 26)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		await _reveal(l, 2.6)
	var meta := Game.meta
	# For pilots who stayed at the station long enough to hear it sung back.
	if meta.wonders.has("lullaby"):
		var hum := UiUtil.label("As you rise, something far below is still humming Okafor's lullaby.", &"", 24,
			UiTheme.ACCENT.lerp(UiTheme.TEXT, 0.4))
		hum.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hum.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		await _reveal(hum, 2.6)
	var found := SignalLogs.found_count(meta.logs_found)
	if found >= SignalLogs.count():
		var heading := UiUtil.label("THE MERIDIAN RECORD", &"TitleLabel", 34, UiTheme.WARN)
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		await _reveal(heading, 0.8)
		for line in RECORD_LINES:
			var l := UiUtil.label(line, &"", 24, UiTheme.WARN.lerp(UiTheme.TEXT, 0.55))
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			await _reveal(l, 2.8)
	else:
		var hint := UiUtil.label("%d of %d Meridian logs recovered. The rest of their story is still down there." % [
			found, SignalLogs.count()], &"DimLabel", 20)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		await _reveal(hint, 1.2)
	var witnessed := Wonders.found_count(meta.wonders)
	var wonders_text := "%d of %d wonders of the trench witnessed." % [witnessed, Wonders.ALL.size()]
	if witnessed < Wonders.ALL.size():
		wonders_text += " The hangar archive says where to look for the rest."
	var wonders := UiUtil.label(wonders_text, &"DimLabel", 20)
	wonders.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	await _reveal(wonders, 0.8)
	var stats := UiUtil.label("Salvage banked: %d     Dives: %d     Victories: %d" % [Game.last_victory_banked,
			meta.dives, meta.wins], &"MonoLabel", 22)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	await _reveal(stats, 1.0)
	var best := "   -   NEW PERSONAL BEST" if Game.last_rank == 0 and meta.records.size() > 1 else ""
	var score := UiUtil.label("SCORE  %s%s" % [UiUtil.thousands(Game.last_score), best], &"MonoLabel", 30,
			UiTheme.WARN if best != "" else UiTheme.ACCENT)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	await _reveal(score, 1.0)
	if meta.pressure_unlocked > 0:
		var unlock := "PRESSURE %d UNLOCKED  -  the trench remembers you. Choose it in the hangar for a harder dive."
		var p := UiUtil.label(unlock % meta.pressure_unlocked, &"", 22, UiTheme.WARN)
		p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		p.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		await _reveal(p, 1.0)
	await _reveal(UiUtil.studio_logo(110.0), 0.4)
	var credits := UiUtil.label("FATHOM  -  a Krypt Keepers game.\n" +
		"Godot Engine 4.5  -  Rock and sand textures: Poly Haven (CC0)  -  Fonts: " +
			"Oxanium, Chakra Petch, Share Tech Mono (SIL OFL)\n" +
		"Every model, creature, cave, sound effect and note of music is generated by code.", &"DimLabel", 18)
	credits.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	await _reveal(credits, 1.0)
	var back := UiUtil.button("Return to hangar", func() -> void: Router.go_to(Router.HANGAR), 340)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_column.add_child(back)
	back.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if _fast:
		return
	var pressed: bool = event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"ui_cancel") \
		or (event is InputEventMouseButton and event.pressed)
	if pressed:
		_fast = true
		get_viewport().set_input_as_handled()
		if _tween and _tween.is_valid():
			_tween.custom_step(60.0)


## Fades [param node] in and holds. The tween belongs to this node, so leaving
## the scene mid-sequence simply stops it.
func _reveal(node: Control, hold: float) -> void:
	node.modulate.a = 0.0
	_column.add_child(node)
	_tween = create_tween()
	_tween.tween_property(node, ^"modulate:a", 1.0, 0.2 if _fast else 1.2)
	_tween.tween_interval(0.0 if _fast else hold)
	await _tween.finished
