extends "res://tools/debug/preview_stage.gd"
## Debug helper: wakes the Ironclad in its vent-field lair and saves
## screenshots of it walking, then cracked open by a vent erupting under it.
## Usage: xvfb-run godot --path . res://tools/debug/preview_ironclad.tscn -- <out_dir> [seed] [film]
## "film" instead saves every frame for eighteen seconds: it walks to a
## noise by a vent, which erupts under it and splits its shell; the sub
## closes in and it rears and crushes down at it; the sub backs off out of
## reach and it spits from its chimneys; then a noise behind it turns it
## round.

var _boss: Ironclad
var _vent: ThermalVent
var _film := false
var _home := Vector2.ZERO


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	stage(BiomeLibrary.FURNACE_ZONE, int(args[1]) if args.size() > 1 and args[1].is_valid_int() else 9102)
	_boss = level.guardian as Ironclad
	for e in level.entities:
		var v := e as ThermalVent
		if v and v.in_lair and (_vent == null or v.pos.distance_to(_boss.pos) < _vent.pos.distance_to(_boss.pos)):
			_vent = v
	_home = level.field.resolve_circle(_boss.pos + Vector2(-6.0, 11.0), 2.0)
	place_sub(_home, 1.35)
	add_hud()
	shot_prefix = "ironclad"
	_boss.take_damage(0.1, _boss.pos)
	_film = args.has("film")
	if _film:
		for i in 540:
			shot_times.append(0.5 + i / 30.0)


func direct(_dt: float) -> void:
	sub.aim = (_boss.pos - sub.pos).normalized()
	sub.run.hull = sub.stats.max_hull
	if _film:
		_direct_film()
		return
	# Call it onto the vent, then set the vent off under it.
	if t < 3.0 and int(t * 10.0) % 10 == 0:
		level.emit_noise(_vent.pos + Vector2(0.0, 3.0), 60.0)
	if t > 2.2 and _vent.state == ThermalVent.State.DORMANT and _boss.exposed <= 0.0:
		_vent.erupt_soon()
	var n := shots_taken()
	if (n == 0 and t >= 1.2) or (n == 1 and _boss.exposed > 0.0 and _boss.exposed < 3.6):
		shoot()
	if shots_taken() >= 2 or t > 25.0:
		get_tree().quit()


func _direct_film() -> void:
	sub.vel = Vector2.ZERO
	# Held off its spit and its crush until each one's turn.
	if t < 9.5:
		_boss.set(&"_spit_cd", 3.0)
	if t < 6.0 or t > 9.0:
		_boss.set(&"_cooldown", maxf(float(_boss.get(&"_cooldown")), 0.5))
	if t < 4.0:
		if int(t * 10.0) % 10 == 0:
			level.emit_noise(_vent.pos + Vector2(0.0, 3.0), 60.0)
		if t > 2.2 and _vent.state == ThermalVent.State.DORMANT and _boss.exposed <= 0.0:
			_vent.erupt_soon()
	elif t < 9.0:
		# In close over it: it rears and crushes down.
		sub.pos = sub.pos.lerp(_boss.pos + Vector2(3.0, 6.5), 0.04)
	elif t < 14.0:
		# Back off out of its reach: it spits.
		sub.pos = sub.pos.lerp(_boss.pos + Vector2(-7.0, 10.0), 0.05)
	elif int(t * 10.0) % 10 == 0:
		# A noise behind it turns it round.
		level.emit_noise(_boss.pos + Vector2(-_boss.heading * 12.0, 1.0), 60.0)
