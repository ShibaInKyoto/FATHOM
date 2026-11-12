class_name ChoirOrgan
extends Creature
## One of the Choir's voice organs. Shielded by its own resonance unless the
## pilot has just answered the song, which leaves every organ open briefly.
## A veined bulb rooted in the rock, a bundle of pipes rising from it with
## glowing, flared mouths turned to the heart (see [ChoirModel]); its pipes
## sway as it hums, swell and flare as it sings with the heart, and while it
## lies open they splay apart, blazing.

var boss: ChoirBoss
var _bulb: MeshInstance3D
var _pipes: Array[Node3D] = []
var _light: OmniLight3D
var _shield_hint := 0.0
var _t := 0.0
## How far it lies open (0 shut, 1 open).
var _open := 0.0


func setup() -> void:
	species = &"choir"
	max_hp = 150.0
	radius = 1.9
	mass = 99.0
	contact_damage = 10.0
	salvage_drop = 20
	glow_color = Color(1.0, 0.35, 0.9)
	super.setup()
	active_radius = 400.0
	lock_facing = true
	facing = (boss.center - pos).normalized()


func build_model() -> void:
	_bulb = add_visual(ChoirModel.organ_body(), ChoirModel.organ_material())
	for pipe: Vector3 in ChoirModel.PIPES:
		var pivot := Node3D.new()
		pivot.position = Vector3(0.9, 0.0, 0.0)
		model.add_child(pivot)
		var mi := MeshInstance3D.new()
		mi.mesh = ChoirModel.organ_pipe(pipe.z)
		mi.material_override = ChoirModel.flesh_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(mi)
		visuals.append(mi)
		_pipes.append(pivot)
	_light = OmniLight3D.new()
	_light.light_color = glow_color
	_light.omni_range = 12.0
	_light.light_energy = 1.5
	_light.light_volumetric_fog_energy = 1.0
	_light.position = Vector3(0, 0, 2.0)
	add_child(_light)
	_pose(0.0)


func behave(delta: float) -> void:
	_t += delta
	_shield_hint = maxf(_shield_hint - delta, 0.0)
	vel = Vector2.ZERO
	_pose(delta)


func _pose(delta: float) -> void:
	var open := boss != null and boss.vulnerable > 0.0
	_open = lerpf(_open, 1.0 if open else 0.0, 1.0 - exp(-8.0 * delta)) if delta > 0.0 else _open
	var song := boss.song_age() if boss else 99.0
	# Each time the heart sings, its pipes swell and flare with it.
	var swell := exp(-song * 3.0)
	var s := 1.0 + sin(_t * (5.0 if open else 2.0)) * (0.05 if open else 0.025)
	_bulb.scale = Vector3(s, s, s)
	for i in _pipes.size():
		var pipe: Vector3 = ChoirModel.PIPES[i]
		var sway := sin(_t * 1.1 + i * 1.7) * 0.04
		var splay := pipe.x * (1.0 + 1.1 * _open) + sway + 0.12 * _open
		_pipes[i].basis = (Basis(Vector3.RIGHT, pipe.y) * Basis(Vector3.BACK, splay)).scaled(
			Vector3.ONE * (1.0 + 0.08 * swell + 0.08 * _open))
	var col := Color(1.0, 0.95, 0.6) if open else glow_color
	_light.light_color = col
	_light.light_energy = 3.0 if open else 1.5 + swell
	for v in visuals:
		v.set_instance_shader_parameter(&"song", song)
		v.set_instance_shader_parameter(&"glow_boost", (1.0 + 0.8 * swell) * (1.0 + 0.35 * _open))
		v.set_instance_shader_parameter(&"tint", Color(1.0, 0.75, 0.35, 0.65 * _open))


func move_and_collide_field(_delta: float, _bounce := 0.1) -> Vector2:
	return Vector2.ZERO


func take_damage(amount: float, from: Vector2, kind: StringName = &"") -> void:
	if boss == null or boss.vulnerable <= 0.0:
		amount *= 0.08
		if _shield_hint <= 0.0:
			_shield_hint = 4.0
			Events.toast.emit("Its resonance shields it. Answer the song first.", UiTheme.WARN)
	super.take_damage(amount, from, kind)


func on_harpoon_hit(_harpoon: Node, damage: float) -> HarpoonReaction:
	take_damage(damage, level.player.pos if level.player else pos, &"harpoon")
	return HarpoonReaction.STICK if alive else HarpoonReaction.IGNORE


func die() -> void:
	if not alive:
		return
	Fx.explosion(level, pos, 5.0)
	Audio.play_at(&"organ_burst", pos, 3.0)
	Events.shake_requested.emit(0.7)
	if boss:
		boss.on_organ_destroyed(self)
	super.die()
