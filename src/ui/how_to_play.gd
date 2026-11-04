class_name HowToPlayPanel
extends CanvasLayer
## Title-screen primer: the core rules of a dive and the full controls list.

const TIPS: PackedStringArray = [
	"Descend through eleven zones to the Hadal Trench and silence what sings there.",
	"Your lamp lights the way and scans creatures held in its beam - but it drains the battery.",
	"Glow bulbs on the walls recharge the battery. Running dark (lamp off) trickle-charges an empty one.",
	"Sonar pings chart the cave and reveal the way down. Every ping is loud: things below will hear it.",
	"Boosting and collisions make noise too. Drift quietly past what you cannot fight.",
	"Fire the harpoon: it flies to the end of its line or the first thing it strikes, then comes straight back.",
	"Hold fire to keep it there: hooked in a cache it reels the catch in, anchored in rock it winches you along.",
	"Harpoon a creature before it notices you for an AMBUSH: double damage.",
	"Decoys stick to the rock and ping on their own. Hunters that hear them go there instead.",
	"Loud noises shake loose stalactites down. Keep out from under them - or lure something beneath.",
	"Find the descent marker to dive deeper. Between zones, pick a module and repair your hull.",
	"Guardians seal the way down out of three biomes. Each has one weakness - scan it, and the codex records it.",
	"Surface at a stop to bank salvage safely - implode and you keep only part of it.",
	"Spend salvage in the hangar on upgrades; research from scans unlocks new submarines.",
	"Some sights down there are wonders. The hangar archive keeps those you witness, and hints where the rest are.",
]


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	var column := UiUtil.modal(self, 0.8, 1100)
	column.add_child(UiUtil.label("HOW TO DIVE", &"TitleLabel"))
	var panel := PanelContainer.new()
	column.add_child(panel)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override(&"separation", 6)
	panel.add_child(inner)
	for tip in TIPS:
		var l := UiUtil.label("-  " + tip, &"", 19)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		inner.add_child(l)
	column.add_child(UiUtil.label("CONTROLS", &"HeaderLabel"))
	var controls := PanelContainer.new()
	controls.add_child(Prompt.controls_grid(19))
	column.add_child(controls)
	var close := UiUtil.button("Back", queue_free)
	column.add_child(close)
	close.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()
