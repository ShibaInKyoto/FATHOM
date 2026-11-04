class_name PauseMenu
extends CanvasLayer
## In-dive pause menu with controls reference and settings.

signal surface_requested
signal photo_requested

var _root: Control
var _settings: SettingsPanel


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func open() -> void:
	if visible:
		return
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	visible = true
	_build()


func close() -> void:
	visible = false
	if _root:
		_root.queue_free()
		_root = null
	for panel in _panels():
		panel.queue_free()
	_settings = null
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN


## Start (or Esc) closes the panel on top, or the menu itself; B does the
## same (the panels handle B themselves first).
func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel")):
		return
	var panels := _panels()
	if panels.is_empty():
		close()
	else:
		panels.back().queue_free()
	get_viewport().set_input_as_handled()


## The panels open over the menu (settings, how to dive, modules), oldest first.
func _panels() -> Array[Node]:
	var out: Array[Node] = []
	for c in get_children():
		if c is CanvasLayer and not c.is_queued_for_deletion():
			out.append(c)
	return out


func _build() -> void:
	var column := UiUtil.modal(self, 0.7, 640)
	_root = column.get_parent().get_parent()
	column.add_child(UiUtil.label("PAUSED", &"TitleLabel"))
	var resume := UiUtil.button("Resume", close)
	column.add_child(resume)
	column.add_child(UiUtil.button("Settings", _open_settings))
	column.add_child(UiUtil.button("How to dive", func() -> void: add_child(HowToPlayPanel.new())))
	if Game.run:
		column.add_child(UiUtil.button("Installed modules (%d)" % Game.run.modules.size(), func() -> void:
			var panel := ModulesPanel.new()
			panel.run = Game.run
			add_child(panel)))
	column.add_child(UiUtil.button("Photo mode", func() -> void: photo_requested.emit()))
	# Abandoning mid-zone counts as losing the sub: only insurance pays out.
	var abandon := "Abandon dive"
	if Game.run:
		abandon += "  (keep %d%% of salvage)" % int(Game.run.stats.insurance * 100)
	column.add_child(UiUtil.button(abandon, func() -> void:
		close()
		surface_requested.emit()))
	column.add_child(UiUtil.spacer(10))
	column.add_child(UiUtil.label("CONTROLS", &"HeaderLabel"))
	column.add_child(Prompt.controls_grid())
	resume.grab_focus()


func _open_settings() -> void:
	_settings = SettingsPanel.new()
	add_child(_settings)
