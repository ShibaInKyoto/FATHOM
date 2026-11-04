class_name LostWreck
extends Entity
## The wreck of the pilot's last submarine, lying in the zone where it was
## lost with the cargo insurance did not cover still aboard. Crushed when it
## imploded, but whole (and dark) when its battery ran dry. Touching it, or
## hooking it with the harpoon, recovers that cargo.

var frame_id: StringName = &"lantern"
var cargo := 0
## "implosion" or "power" (see [member MetaState.wreck_kind]).
var kind := "implosion"
var _recovered := false
var _announced := false
var _t := 0.0
var _beacon: OmniLight3D


func setup() -> void:
	radius = 1.6
	active_radius = 90.0
	targetable = true
	var model := SubmarineModel.new()
	add_child(model)
	var crushed := kind != "power"
	model.build(frame_id, Game.livery(frame_id))
	model.fit_equipment(SubStats.build(frame_id, {}, []).tools, {}, [])
	model.darken_hull(0.6 if crushed else 0.35)
	model.set_cockpit_glow(0.0)
	if crushed:
		# Crumpled by the pressure, lying crooked where it came to rest.
		model.scale = Vector3(0.92, 0.62, 0.8)
		model.rotation = Vector3(0.45, level.rng.randf_range(-0.6, 0.6), level.rng.randf_range(-0.6, 0.6))
	else:
		# Whole, settled on its skids, every light out.
		model.rotation = Vector3(0.08, level.rng.randf_range(-0.25, 0.25), level.rng.randf_range(-0.12, 0.12))
	var leak := Fx.bubble_emitter()
	leak.amount_ratio = 0.35 if crushed else 0.08
	leak.position = Vector3(0.0, 0.6, 0.0)
	add_child(leak)
	leak.emitting = true
	_beacon = OmniLight3D.new()
	_beacon.light_color = Color(1.0, 0.25, 0.15)
	_beacon.omni_range = 9.0
	_beacon.position = Vector3(0.0, 1.2, 1.0)
	add_child(_beacon)


func display_name() -> String:
	var frame := Catalog.frame(frame_id)
	return frame.name if frame else "submarine"


func tick(delta: float) -> void:
	_t += delta
	if not _announced:
		_announced = true
		var how := "dark but whole" if kind == "power" else "crushed"
		Events.toast.emit("The wreck of your %s lies somewhere in this zone, %s, %d salvage still aboard." %
			[display_name(), how, cargo], UiTheme.WARN)
	# A slow distress blink.
	_beacon.light_energy = 2.2 if fmod(_t, 2.0) < 0.25 else 0.15
	vel = vel.lerp(Vector2(0, -0.5), 1.0 - exp(-1.0 * delta))
	move_and_collide_field(delta, 0.0)
	var sub := level.player
	if sub and sub.alive and sub.pos.distance_to(pos) < Submarine.RADIUS + radius + 0.4:
		recover(sub)


func on_harpoon_hit(_harpoon: Node, _damage: float) -> HarpoonReaction:
	return HarpoonReaction.DRAG


func on_reeled_in(sub: Submarine) -> void:
	recover(sub)


func on_sonar(_origin: Vector2, _mark_time: float) -> void:
	_t = 0.0


## Spills the lost cargo and closes the account of the last dive.
func recover(_sub: Submarine) -> void:
	if _recovered:
		return
	_recovered = true
	Game.meta.clear_wreck()
	Audio.play_at(&"log_found", pos, 0.0)
	Fx.sparkle(level, pos, Color(1.0, 0.8, 0.3))
	Fx.bubble_burst(level, pos, 40, 1.6)
	Pickup.scatter(level, pos, &"salvage", cargo, 1.8)
	Events.toast.emit("Recovered your %s's cargo: %d salvage." % [display_name(), cargo], UiTheme.GOOD)
	despawn()
