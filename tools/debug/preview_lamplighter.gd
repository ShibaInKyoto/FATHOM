extends "res://tools/debug/preview_stage.gd"
## Debug helper: wakes the Lamplighter in the reef lair and saves screenshots
## of her lure in the dark, the lure going dark before a charge, and her
## dazzled by the lamp.
## Usage: xvfb-run godot --path . res://tools/debug/preview_lamplighter.tscn -- <out_dir> [film]
## "film" instead saves every frame for fifteen seconds as she goes through
## her moods, side on: stalking, winding up and charging, dazzled (eyes
## squeezed shut), guarding (eyes narrowed), and lurking with her lure dark.

var _angler: Lamplighter
var _far := Vector2.ZERO
var _film := false
var _beat := 0


func _ready() -> void:
	stage(BiomeLibrary.ANGLER_ZONE, 77)
	_angler = level.guardian as Lamplighter
	_far = level.layout.field.resolve_circle(_angler.lair_center - Vector2(_angler.lair_radius.x * 0.45, 0.0), 2.0)
	place_sub(_far, 1.3)
	sub.lamp_on = false
	add_hud()
	shot_prefix = "angler"
	_angler.take_damage(0.1, _angler.pos)
	_film = OS.get_cmdline_user_args().size() > 1 and OS.get_cmdline_user_args()[1] == "film"
	if _film:
		for i in 450:
			shot_times.append(0.5 + i / 30.0)


func direct(_dt: float) -> void:
	sub.run.hull = sub.stats.max_hull
	if _film:
		_direct_film()
		return
	var n := shots_taken()
	if n < 2:
		sub.pos = _far
		sub.vel = Vector2.ZERO
		sub.aim = (_angler.head_pos() - sub.pos).normalized()
		sub.lamp_on = n == 1
	elif _angler.state == Lamplighter.State.STALK:
		sub.pos = _angler.head_pos() + _angler.facing * 9.0
		sub.vel = Vector2.ZERO
		sub.aim = (_angler.head_pos() - sub.pos).normalized()
		sub.lamp_on = true
	if (n == 0 and t >= 1.2) or (n == 1 and _angler.state == Lamplighter.State.WINDUP and t > 3.0) \
			or (n == 2 and _angler.state == Lamplighter.State.DAZZLED):
		shoot()
	if shots_taken() >= 3 or t > 30.0:
		get_tree().quit()


## The film: the sub holds still, dark, well off to one side; she is put
## through each of her moods in turn.
func _direct_film() -> void:
	sub.lamp_on = false
	sub.vel = Vector2.ZERO
	sub.pos = _angler.pos + Vector2(-14.0, 3.0)
	sub.aim = (_angler.pos - sub.pos).normalized()
	var a := _angler
	var beats := [3.0, 5.4, 9.0, 11.5]
	if _beat < beats.size() and t >= beats[_beat]:
		match _beat:
			0:
				a.call(&"_begin_windup")
			1:
				a.call(&"_be_dazzled")
			2:
				a.call(&"_recover", 0.5)
				a.raise_guard()
			3:
				a.call(&"_begin_lurk")
		_beat += 1
	if a.state == Lamplighter.State.STALK and _beat == 0:
		a.set(&"_cooldown", 1.0)
	if a.state == Lamplighter.State.STALK and _beat >= 3:
		a.set(&"_cooldown", 1.0)
