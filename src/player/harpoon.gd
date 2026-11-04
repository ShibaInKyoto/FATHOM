class_name Harpoon
extends Node3D
## The submarine's tethered harpoon. A press sends it out to the end of its
## line or the first thing in the way, straight through the crosshair. A tap
## brings it straight back from whatever it struck: it spears a creature
## (and pulls free once the blow lands) and comes home. Held, it stays put:
## anchored in rock it winches the submarine along, hooked in a cache it
## reels the catch in; let go and it comes home. A press while it is on its
## way home fires again the moment it is back.

enum State { IDLE, FLYING, ANCHORED, ATTACHED, RETRACTING }

const SPEED := 48.0
const RETRACT_SPEED := 90.0
## A dragged catch that comes no closer for this long (snagged on rock) is let go.
const DRAG_STALL := 1.2

var state := State.IDLE
var tip := Vector2.ZERO
var direction := Vector2.RIGHT
var target: Entity
var holding := false
## Pressed again on its way home: fire as soon as it is back.
var _queued := false
## The player's own shot: aimed from the muzzle through the crosshair.
var _at_crosshair := false

var _sub: Submarine
var _travelled := 0.0
var _stick_timer := 0.0
var _drag_closest := INF
var _drag_stall := 0.0
var _target_offset := Vector2.ZERO
var _cable: MeshInstance3D
var _spear: Node3D


func setup(sub: Submarine) -> void:
	_sub = sub
	top_level = true
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.75, 0.78, 0.8)
	steel.metallic = 0.9
	steel.roughness = 0.3
	_spear = Node3D.new()
	add_child(_spear)
	# The spear that flies is the one loaded in the launcher, cards and all.
	var loaded := sub.model.harpoon_spear() if sub.model else null
	if loaded:
		var copy := loaded.duplicate() as Node3D
		copy.transform = Transform3D(Basis().scaled(Vector3.ONE * 1.8), Vector3(-0.08, 0, 0))
		copy.visible = true
		_spear.add_child(copy)
	var shaft := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.11
	cone.height = 0.6
	cone.radial_segments = 8
	shaft.mesh = cone
	shaft.material_override = steel
	shaft.rotation_degrees = Vector3(0, 0, -90)
	if loaded == null:
		_spear.add_child(shaft)
	else:
		shaft.free()
	var glow := MeshInstance3D.new()
	glow.mesh = MeshKit.sphere(0.07)
	glow.material_override = MeshKit.emissive_material(Color(1.0, 0.5, 0.2), 6.0)
	glow.position = Vector3(-0.25, 0, 0)
	_spear.add_child(glow)
	_cable = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.03
	cyl.bottom_radius = 0.03
	cyl.height = 1.0
	cyl.radial_segments = 6
	cyl.rings = 1
	_cable.mesh = cyl
	var cable_mat := StandardMaterial3D.new()
	cable_mat.albedo_color = Color(0.9, 0.8, 0.5)
	cable_mat.emission_enabled = true
	cable_mat.emission = Color(0.9, 0.7, 0.4)
	cable_mat.emission_energy_multiplier = 0.4
	_cable.material_override = cable_mat
	_cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cable)
	visible = false


func _origin() -> Vector2:
	return _sub.launch_point(&"harpoon", 1.2)


## The trigger goes down: fires along [param aim], or (for the player, with
## [param at_crosshair]) from the muzzle through the crosshair. Pressed on
## its way home, it fires again the moment it is back.
func fire(aim: Vector2, at_crosshair := false) -> void:
	holding = true
	_at_crosshair = at_crosshair
	if state == State.RETRACTING:
		_queued = true
		return
	if state != State.IDLE or not _sub.alive:
		return
	_launch(aim)


func _launch(aim: Vector2) -> void:
	state = State.FLYING
	tip = _origin()
	direction = _sub.aim_from(tip) if _at_crosshair else aim.normalized()
	_travelled = 0.0
	visible = true
	_sub.model.set_harpoon_loaded(false)
	Audio.play(&"harpoon_fire", -3.0)
	_sub.level.emit_noise(_sub.pos, 8.0 * _sub.stats.noise_mult, _sub)


## The trigger comes up. Out on its line it carries on to whatever it
## strikes and then comes home; anchored or reeling a catch, it lets go now.
func release() -> void:
	holding = false
	if state == State.ANCHORED or state == State.ATTACHED and _stick_timer <= 0.0:
		_retract()


## A tap of the trigger (for scripted pilots): out, and straight back.
func throw(aim: Vector2) -> void:
	fire(aim)
	release()


func tick(delta: float) -> void:
	match state:
		State.FLYING:
			_fly(delta)
		State.ANCHORED:
			_winch(delta)
		State.ATTACHED:
			_drag(delta)
		State.RETRACTING:
			var to := _sub.pos - tip
			var step := RETRACT_SPEED * delta
			if to.length() <= step + 1.0:
				state = State.IDLE
				visible = false
				_sub.model.set_harpoon_loaded(true)
				if _queued and _sub.alive:
					_queued = false
					_launch(_sub.aim)
			else:
				tip += to.normalized() * step
	if visible:
		_update_visuals()


func _fly(delta: float) -> void:
	var step := SPEED * delta
	var next := tip + direction * step
	var hit_target := _sub.level.first_target_on_segment(tip, next, 0.2)
	var t_wall := _sub.level.field.cast(tip, next, 0.05)
	if hit_target and (t_wall >= 1.0 or tip.distance_to(hit_target.pos) < step * t_wall + hit_target.radius):
		_hit_entity(hit_target)
		return
	if t_wall < 1.0:
		tip = tip.lerp(next, t_wall)
		state = State.ANCHORED
		Audio.play_at(&"harpoon_wall", tip, -2.0)
		Fx.sparks(_sub.level, tip)
		if not holding:
			_retract()
		return
	tip = next
	_travelled += step
	if _travelled >= _sub.stats.harpoon_range:
		_retract()


func _hit_entity(e: Entity) -> void:
	var reaction := e.on_harpoon_hit(self, _sub.stats.harpoon_damage)
	if e is Creature and _sub.stats.harpoon_leech > 0.0:
		_sub.add_battery(_sub.stats.harpoon_leech)
	match reaction:
		Entity.HarpoonReaction.DRAG:
			tip = e.pos
			Audio.play_at(&"harpoon_hook", tip, -2.0)
			if not holding:
				# A tap: the barb glances off and comes home.
				_retract()
				return
			target = e
			_target_offset = Vector2.ZERO
			state = State.ATTACHED
			_drag_closest = INF
			_drag_stall = 0.0
		Entity.HarpoonReaction.STICK:
			Events.hitstop.emit(0.035)
			Events.shake_requested.emit(0.15)
			target = e
			_target_offset = tip - e.pos
			state = State.ATTACHED
			_stick_timer = 0.35
			Audio.play_at(&"harpoon_flesh", tip, 0.0)
		_:
			tip = e.pos
			_retract()


## Pulls the submarine towards the anchor while fire is held.
func _winch(delta: float) -> void:
	var to := tip - _sub.pos
	var dist := to.length()
	if dist < 3.0 or not holding or dist > _sub.stats.harpoon_range * 1.6:
		_retract()
		return
	var pull := to / dist * _sub.stats.harpoon_reel
	_sub.vel = _sub.vel.lerp(pull, 1.0 - exp(-3.0 * delta))


func _drag(delta: float) -> void:
	if target == null or not is_instance_valid(target) or not target.alive:
		_retract()
		return
	if _stick_timer > 0.0:
		_stick_timer -= delta
		tip = target.pos + _target_offset
		if _stick_timer <= 0.0:
			_retract()
		return
	tip = target.pos
	var to := _sub.pos - target.pos
	var dist := to.length()
	if dist < Submarine.RADIUS + target.radius + 0.8:
		if target.has_method(&"on_reeled_in"):
			target.call(&"on_reeled_in", _sub)
		_retract()
		return
	target.vel = target.vel.lerp(to / dist * _sub.stats.harpoon_reel, 1.0 - exp(-5.0 * delta))
	if dist < _drag_closest - 0.5:
		_drag_closest = dist
		_drag_stall = 0.0
	else:
		_drag_stall += delta
	if dist > _sub.stats.harpoon_range * 2.0 or _drag_stall > DRAG_STALL:
		_retract()


func _retract() -> void:
	state = State.RETRACTING
	target = null
	_queued = false


func _update_visuals() -> void:
	var a := _origin()
	var a3 := Vector3(a.x, a.y, 0.0)
	var b3 := Vector3(tip.x, tip.y, 0.0)
	_spear.global_position = b3
	var dir := direction if state == State.FLYING else (tip - a).normalized()
	if state == State.RETRACTING:
		dir = (tip - _sub.pos).normalized()
	_spear.rotation = Vector3(0, 0, dir.angle())
	var span := b3 - a3
	var length := span.length()
	_cable.visible = length > 0.2
	if _cable.visible:
		var y := span / length
		var x := y.cross(Vector3.BACK).normalized()
		var z := x.cross(y)
		_cable.global_transform = Transform3D(Basis(x, y * length, z), (a3 + b3) * 0.5)
