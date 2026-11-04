class_name Tutorial
extends CanvasLayer
## Contextual hints for a pilot's first dive. Each step shows until its
## condition is met (or it times out), then the next one becomes eligible.

var sub: Submarine
var level: Level

var _panel: PanelContainer
var _label: Label
var _steps: Array[StringName] = []
var _current: StringName = &""
var _shown_time := 0.0
var _start_pos := Vector2.ZERO
var _pinged := false
var _scanned := false
var _fired := false
var _elapsed := 0.0


static func wanted() -> bool:
	return not Game.meta.tutorial_done and Game.run and Game.run.zone == 0 and not Autopilot.requested()


func bind(p_sub: Submarine, p_level: Level) -> void:
	sub = p_sub
	level = p_level
	_start_pos = sub.pos
	Events.sonar_pinged.connect(func(_p: Vector2, _r: float) -> void: _pinged = true)
	Events.creature_scanned.connect(func(_id: StringName, _f: bool) -> void: _scanned = true)
	_steps = [&"move", &"ping", &"descent", &"scan", &"harpoon", &"noise", &"battery", &"flare"]


func _text(step: StringName) -> String:
	match step:
		&"move":
			return "%s thrust     %s aim the lamp" % [Prompt.key(&"move"), Prompt.key(&"aim")]
		&"ping":
			return "%s sonar ping - charts the cave and finds the way down.  Creatures hear it too." % Prompt.key(&"ping")
		&"descent":
			return "Follow the green marker to the DESCENT at the bottom of the zone.  %s shows the chart." \
				% Prompt.key(&"map")
		&"scan":
			return "Keep your lamp on a creature to scan it.  Scans earn research for new submarines."
		&"harpoon":
			return "%s harpoon - tap to spear creatures; hold to reel caches in or winch yourself to rock." \
				% Prompt.key(&"fire")
		&"noise":
			return "Moving fast is loud (the faint ring).  Hunters follow noise.  %s boosts - loudly." % Prompt.key(&"boost")
		&"battery":
			return "The lamp drains battery.  Touch glowing bulbs on the walls to recharge.  %s toggles the lamp." \
				% Prompt.key(&"lamp")
		&"flare":
			return "%s fires a flare - a decoy light that draws predators away from you." % Prompt.key(&"tool")
	return ""


## Whether a step's hint should appear now.
func _ready_to_show(step: StringName) -> bool:
	match step:
		&"descent":
			return level.exit_known
		&"scan":
			return sub.scan_target != null
		&"harpoon":
			return _cache_near()
		&"noise":
			return _elapsed > 40.0
		&"battery":
			return sub.run.battery < sub.stats.max_battery * 0.6
		&"flare":
			return _elapsed > 75.0
	return true


## Whether the hint has done its job and can disappear.
func _finished(step: StringName) -> bool:
	match step:
		&"move":
			return sub.pos.distance_to(_start_pos) > 12.0
		&"ping":
			return _pinged
		&"scan":
			return _scanned or _shown_time > 12.0
		&"harpoon":
			return _fired or _shown_time > 12.0
		&"descent":
			return _shown_time > 7.0
	return _shown_time > 8.5


func _ready() -> void:
	layer = 9
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.get_theme()
	add_child(root)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.offset_left = -560
	_panel.offset_right = 560
	_panel.offset_top = -190
	_panel.offset_bottom = -130
	_panel.add_theme_stylebox_override(&"panel", UiTheme.panel_style(Color(0.01, 0.06, 0.09, 0.85), UiTheme.ACCENT, 1, 8))
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.modulate.a = 0.0
	root.add_child(_panel)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(_label)


func _process(delta: float) -> void:
	if sub == null or not sub.alive:
		_panel.modulate.a = move_toward(_panel.modulate.a, 0.0, delta * 3.0)
		return
	_elapsed += delta
	_fired = _fired or sub.harpoon.state != Harpoon.State.IDLE
	if _current == &"":
		for step in _steps:
			if _ready_to_show(step):
				_current = step
				_steps.erase(step)
				_shown_time = 0.0
				Audio.play_ui(&"ui_hover", -4.0)
				break
	else:
		_shown_time += delta
		_label.text = _text(_current)
		if _finished(_current):
			_current = &""
	var target_alpha := 0.0 if _current == &"" else 1.0
	_panel.modulate.a = move_toward(_panel.modulate.a, target_alpha, delta * 3.0)


func _cache_near() -> bool:
	for e in level.targets_in_radius(sub.pos, 16.0):
		if e is SalvageCache:
			return true
	return false
