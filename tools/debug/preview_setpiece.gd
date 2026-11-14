extends "res://tools/debug/preview_stage.gd"
## Debug helper: photographs one of the set pieces (vent, stalactite, bulb,
## beacon, probe, marker, wreck) from cameras a few metres off, then from the
## dive camera. "film" instead films it in action (erupting, falling,
## harvested, pinging, blinking, flowing) from the close camera.
## Usage: xvfb-run godot --path . res://tools/debug/preview_setpiece.tscn -- <out_dir> <piece> [seed] [film] [dark]

var _piece := ""
var _cam: Camera3D
var _views: Array = []
var _focus := Vector3.ZERO
var _entity: Entity
var _film := false
var _dark := false
var _acted := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_piece = args[1] if args.size() > 1 else "vent"
	var run_seed := int(args[2]) if args.size() > 2 and args[2].is_valid_int() else 7
	_film = args.has("film")
	_dark = args.has("dark")
	var zone := 0
	var event := &""
	match _piece:
		"vent":
			zone = 6
		"stalactite":
			zone = 4
		"bulb":
			zone = 2
		"beacon", "probe":
			zone = 3
		"marker":
			zone = 1
		"wreck":
			zone = 3
			event = &"wrecks"
	stage(zone, run_seed, &"lantern", _piece == "wreck", event)
	var normal := Vector2.UP
	match _piece:
		"vent":
			_entity = find_entity(func(e: Entity) -> bool: return e is ThermalVent)
			normal = (_entity as ThermalVent).normal
		"stalactite":
			_entity = find_entity(func(e: Entity) -> bool: return e is Stalactite)
			normal = Vector2.DOWN
		"bulb":
			_entity = find_entity(func(e: Entity) -> bool: return e is GlowBulb)
			normal = (_entity as GlowBulb).normal
		"beacon":
			var beacon := LogBeacon.new()
			beacon.log_id = &"log_01"
			beacon.pos = _floor_spot()
			level.add_entity(beacon)
			_entity = beacon
		"probe":
			var probe := SurveyProbe.new()
			probe.pos = _floor_spot()
			level.add_entity(probe)
			_entity = probe
	var at := _entity.pos if _entity else Vector2.ZERO
	if _piece == "marker":
		at = level.layout.exit
		normal = Vector2.UP
	if _piece == "wreck":
		var spots := Wrecks.scatter(level, level.rng, PackedVector2Array())
		at = spots[0] if not spots.is_empty() else level.layout.start
	_focus = Vector3(at.x, at.y, 0.0)
	var n := Vector3(normal.x, normal.y, 0.0)
	var across := Vector3(-normal.y, normal.x, 0.0)
	var reach := 9.0 if _piece == "wreck" or _piece == "marker" else 3.2
	var lift := 2.5 if _piece == "wreck" else 0.6
	var look := _focus + n * lift
	_views = [[look + Vector3(0, 0, reach * 1.6) + n * reach * 0.3, look],
		[look + across * reach * 1.1 + Vector3(0, 0, reach) + n * reach * 0.4, look],
		[look - across * reach * 1.1 + Vector3(0, 0, reach * 0.9) + n * reach * 0.2, look],
		[look + Vector3(0, 0, reach * 0.7) + n * reach * 0.15, look]]
	place_sub(at + normal * 7.0 + Vector2(-22.0 if _piece == "wreck" else -5.0, 0.0), 1.0)
	add_hud()
	shot_prefix = _piece
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.45
	fill.rotation_degrees = Vector3(-35, 20, 0)
	add_child(fill)
	_cam = Camera3D.new()
	_cam.fov = 42.0
	add_child(_cam)
	_cam.current = true
	shot_times = [1.0, 1.4, 1.8, 2.2, 2.8]
	if _film and _piece == "stalactite":
		# Wide enough to watch it come loose, fall and break on the floor.
		_views[0] = [look + Vector3(0, -3.5, 15.0), look + Vector3(0, -3.0, 0)]
	if _film:
		shot_times = []
		for i in 90:
			shot_times.append(1.0 + i / 15.0)


## A point on open floor a little away from the start, clear of boulders.
func _floor_spot() -> Vector2:
	for a: LevelLayout.Anchor in level.layout.anchors:
		if a.normal.y < 0.9 or a.pos.distance_to(level.layout.start) < 25.0 \
				or level.field.sample(a.pos + a.normal * 3.0) < 2.5:
			continue
		var clear := true
		for q in level.boulders:
			clear = clear and q.distance_to(a.pos) > 7.0
		if clear:
			return a.pos + a.normal * 0.9
	return level.layout.start


func direct(_dt: float) -> void:
	sub.run.hull = sub.stats.max_hull
	if _dark:
		sub.lamp_on = false
	sub.vel = Vector2.ZERO
	var i := shots_taken()
	if _film:
		i = 0
		_act()
	# The last still is from the dive camera.
	if not _film and i >= _views.size():
		_cam.current = false
		camera.make_current()
		return
	_cam.position = _views[mini(i, _views.size() - 1)][0]
	_cam.look_at(_views[mini(i, _views.size() - 1)][1])


## Sets the piece going for a film.
func _act() -> void:
	if _acted or t < 1.5:
		return
	_acted = true
	if _entity is ThermalVent:
		(_entity as ThermalVent).erupt_soon()
	elif _entity is Stalactite:
		(_entity as Stalactite).shake_loose()
	elif _entity is GlowBulb:
		# Harvested from afar, so the sub does not hide it.
		_entity.call(&"_harvest", sub)
