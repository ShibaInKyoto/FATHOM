class_name CreditsPanel
extends CanvasLayer
## Who made what, and the licenses the game ships under (the engine's MIT
## notice and its third-party components are required to be shown).


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	var column := UiUtil.modal(self, 0.85, 1100)
	column.add_child(UiUtil.label("CREDITS", &"TitleLabel"))
	column.add_child(UiUtil.studio_logo(150.0))
	for line: String in [
		"FATHOM is a Krypt Keepers game.",
		"Rock and sand textures: Poly Haven (CC0).  Fonts: Oxanium, Chakra Petch and Share Tech Mono " +
			"(SIL Open Font License 1.1).",
		"Made with the Godot Engine (godotengine.org).",
	]:
		var l := UiUtil.label(line, &"", 20)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(l)
	column.add_child(UiUtil.label("LICENSES", &"HeaderLabel"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var text := UiUtil.label(license_summary(), &"DimLabel", 15)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(text)
	var close := UiUtil.button("Back", queue_free)
	column.add_child(close)
	close.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()


## The engine license and a list of the components it bundles (the full
## texts ship in THIRD_PARTY_LICENSES.txt beside the executable).
static func license_summary() -> String:
	var lines := PackedStringArray(["Godot Engine", Engine.get_license_text(), "",
		"Godot bundles these third-party components (full license texts are in THIRD_PARTY_LICENSES.txt):"])
	for info: Dictionary in Engine.get_copyright_info():
		var ids := PackedStringArray()
		for part: Dictionary in info.parts:
			if not ids.has(part.license):
				ids.append(part.license)
		lines.append("  %s  -  %s" % [info.name, ", ".join(ids)])
	return "\n".join(lines)


## The engine license followed by every third-party component and the full
## text of each license (written into the release archive).
static func license_text() -> String:
	var parts := PackedStringArray(["Godot Engine\n" + Engine.get_license_text()])
	var licenses := Engine.get_license_info()
	for info: Dictionary in Engine.get_copyright_info():
		var lines := PackedStringArray([String(info.name)])
		for part: Dictionary in info.parts:
			lines.append("  Files: %s" % ", ".join(part.files))
			for c in part.copyright:
				lines.append("  (c) %s" % c)
			lines.append("  License: %s" % part.license)
		parts.append("\n".join(lines))
	for key: String in licenses:
		parts.append("%s\n%s" % [key, licenses[key]])
	return "\n\n".join(parts)
