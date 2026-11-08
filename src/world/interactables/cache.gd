class_name SalvageCache
extends Entity
## A sealed salvage crate from a lost expedition (see [CrateModel]). Ram it,
## or hook it with the harpoon to drag it in; it bursts open into salvage and
## supplies.

## Base salvage inside; scaled by depth when populated.
var salvage := 10
var rich := false
var _opened := false
var _beacon: MeshInstance3D
var _t := 0.0


func setup() -> void:
	radius = 1.0
	active_radius = 70.0
	targetable = true
	var body := Node3D.new()
	body.rotation.z = level.rng.randf_range(-0.4, 0.4)
	add_child(body)
	for mesh: Mesh in [CrateModel.base(), CrateModel.lid()]:
		var part := MeshInstance3D.new()
		part.mesh = mesh
		body.add_child(part)
	_beacon = CrateModel.beacon(Color(1.0, 0.75, 0.2) if not rich else Color(0.4, 1.0, 0.5))
	body.add_child(_beacon)


func tick(delta: float) -> void:
	_t += delta
	_beacon.visible = fmod(_t, 1.2) < 0.6
	vel = vel.lerp(Vector2(0, -0.6), 1.0 - exp(-1.2 * delta))
	move_and_collide_field(delta, 0.1)
	var sub := level.player
	if sub and sub.alive and sub.pos.distance_to(pos) < Submarine.RADIUS + radius + 0.3:
		open(sub)


func on_harpoon_hit(_harpoon: Node, _damage: float) -> HarpoonReaction:
	return HarpoonReaction.DRAG


func on_reeled_in(sub: Submarine) -> void:
	open(sub)


func on_sonar(_origin: Vector2, _mark_time: float) -> void:
	_t = 0.0


func open(sub: Submarine) -> void:
	if _opened:
		return
	_opened = true
	Events.cache_opened.emit(pos)
	Audio.play_at(&"cache_open", pos, 0.0)
	Fx.sparkle(level, pos, Color(1.0, 0.8, 0.3))
	Fx.bubble_burst(level, pos, 24, 1.0)
	Pickup.scatter(level, pos, &"salvage", salvage, 1.4)
	var extras := 1 + sub.stats.cache_bonus + (1 if rich else 0)
	for i in extras:
		var roll := level.rng.randf()
		if roll < 0.4:
			Pickup.scatter(level, pos, &"repair", 20, 1.0)
		elif roll < 0.75:
			Pickup.scatter(level, pos, &"power", 25, 1.0)
		else:
			_resupply(sub)
	despawn()


func _resupply(sub: Submarine) -> void:
	var run := sub.run
	if run.stats.torpedo_capacity > run.torpedoes or run.stats.flare_capacity > run.flares \
			or run.stats.decoy_capacity > run.decoys:
		run.torpedoes = mini(run.torpedoes + 2, run.stats.torpedo_capacity)
		run.flares = mini(run.flares + 2, run.stats.flare_capacity)
		run.decoys = mini(run.decoys + 1, run.stats.decoy_capacity)
		Events.toast.emit("Ammunition resupplied", UiTheme.WARN)
	else:
		Pickup.scatter(level, pos, &"salvage", int(salvage * 0.5), 1.2)
