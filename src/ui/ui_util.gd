class_name UiUtil
extends RefCounted
## Small helpers for building UI in code.


static func label(text: String, variation: StringName = &"", size := 0, color := Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	if variation != &"":
		l.theme_type_variation = variation
	if size > 0:
		l.add_theme_font_size_override(&"font_size", size)
	if color.a > 0.0:
		l.add_theme_color_override(&"font_color", color)
	return l


static func button(text: String, on_pressed: Callable, min_width := 260) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 52)
	b.pressed.connect(func() -> void:
		Audio.play_ui(&"ui_click")
		on_pressed.call())
	b.mouse_entered.connect(func() -> void: Audio.play_ui(&"ui_hover", -10.0))
	b.focus_entered.connect(func() -> void: Audio.play_ui(&"ui_hover", -12.0))
	return b


## Full-screen dimmer with a centered column; returns the column.
static func modal(parent: Node, dim := 0.6, width := 720) -> VBoxContainer:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.get_theme()
	parent.add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.02, 0.04, dim)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(width, 0)
	column.add_theme_constant_override(&"separation", 14)
	center.add_child(column)
	return column


static func spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


static func clear(node: Node) -> void:
	for c in node.get_children():
		c.queue_free()


## Formats an integer with thousands separators: 12345 -> "12,345".
static func thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


static func format_time(seconds: float) -> String:
	var s := int(seconds)
	@warning_ignore("integer_division")
	return "%d:%02d" % [s / 60, s % 60]


## The Krypt Keepers logo, [param height] pixels tall and centred.
static func studio_logo(height: float) -> TextureRect:
	var logo := TextureRect.new()
	logo.texture = load("res://assets/branding/krypt_keepers_logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(0.0, height)
	logo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return logo
