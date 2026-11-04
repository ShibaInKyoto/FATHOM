class_name Prompt
extends RefCounted
## Human-readable button names for the active input device.

const GAMEPAD: Dictionary[StringName, String] = {
	&"move": "L-Stick", &"aim": "R-Stick", &"fire": "RT", &"tool": "RB", &"cycle_tool": "LB",
	&"ping": "A", &"boost": "LT", &"lamp": "Y", &"map": "Back", &"pause": "Start",
}


## Rows of [description, keyboard action (or fixed text), gamepad] for the
## controls reference; keyboard actions show their current binding.
const CONTROLS := [
	["Move", &"move", "Left stick"],
	["Aim lamp and tools", "Mouse", "Right stick"],
	["Harpoon (hold to winch)", &"fire", "RT"],
	["Use tool", &"tool", "RB"],
	["Cycle tool", &"cycle_tool", "LB"],
	["Sonar ping", &"ping", "A"],
	["Boost", &"boost", "LT"],
	["Toggle lamp", &"lamp", "Y"],
	["Sonar chart", &"map", "Back"],
	["Pick a module at stops", "1 / 2 / 3", "D-pad + A"],
	["Pause", "Esc", "Start"],
	["Back out of a menu", "Esc", "B"],
	["Switch hangar tabs", "Q / E", "LB / RB"],
	["Fullscreen / screenshot", "F11 / F12", "-"],
]


## A grid listing every control for keyboard and gamepad.
static func controls_grid(font_size := 20) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 30)
	for row: Array in CONTROLS:
		var keys: String = keyboard_name(row[1]) if row[1] is StringName else row[1]
		grid.add_child(UiUtil.label(row[0], &"DimLabel", font_size))
		grid.add_child(UiUtil.label(keys, &"MonoLabel", font_size))
		grid.add_child(UiUtil.label(row[2], &"MonoLabel", font_size))
	return grid


## The button for [param action] on the device in use, in brackets.
static func key(action: StringName) -> String:
	if Settings.using_gamepad:
		return "[%s]" % GAMEPAD.get(action, String(action))
	return "[%s]" % keyboard_name(action)


## The current keyboard or mouse binding of [param action] ("move" lists
## all four thrust keys, e.g. WASD, or ZQSD on an AZERTY keyboard).
static func keyboard_name(action: StringName) -> String:
	match action:
		&"move":
			var keys := PackedStringArray()
			for dir: StringName in [&"move_up", &"move_left", &"move_down", &"move_right"]:
				keys.append(Settings.binding_name(dir))
			var short := keys[0].length() == 1 and keys[1].length() == 1 and keys[2].length() == 1 \
				and keys[3].length() == 1
			return "".join(keys) if short else "/".join(keys)
		&"aim":
			return "Mouse"
		&"pause":
			return "Esc"
	return Settings.binding_name(action)
