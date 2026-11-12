extends "res://tools/debug/preview_stage.gd"
## Debug helper: a creature (its pack, or its school) where the game would
## put it in a zone it lives in, going about its business by its own
## behaviour, to judge whether its animation matches how it really moves.
## For four seconds the sub idles dark a way off; then it closes in, lamp on,
## and pings; from ten seconds on it backs away. A camera follows the
## creature at the dive camera's lens, a frame every fifteenth of a second,
## and every step is logged to <out_dir>/log.csv: where it is and how fast
## it moves, which way its body points and which way it faces, its state,
## its stroke and its gait.
## Usage: xvfb-run godot --path . res://tools/debug/preview_ingame.tscn -- <out_dir> <species> [seed] [distance]
## (species: any in LevelPopulator.SPECIES, "mimic", or a guardian, staged in
## its lair: "lamplighter", "mother", "ironclad").

const FPS := 15.0
const LENGTH := 15.0
const GUARDIANS: Dictionary[StringName, int] = {&"lamplighter": BiomeLibrary.ANGLER_ZONE,
	&"mother": BiomeLibrary.LAIR_ZONE, &"ironclad": BiomeLibrary.FURNACE_ZONE}

var _id := &""
var _crits: Array[Creature] = []
var _cam: Camera3D
var _log: FileAccess
var _distance := 18.0
var _pinged := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_id = StringName(args[1]) if args.size() > 1 else &"lancer"
	var run_seed := int(args[2]) if args.size() > 2 else 11
	_distance = float(args[3]) if args.size() > 3 else 18.0
	if GUARDIANS.has(_id):
		_stage_guardian(run_seed)
		return
	stage(_zone_for(_id), run_seed, &"lantern", true)
	var spot := {}
	for _try in 40:
		spot = LevelPopulator._creature_spot(level, &"lancer" if _id == &"mimic" else _id, PackedVector2Array())
		if not spot.is_empty():
			break
	var count: int = LevelPopulator.PACKS.get(_id, 1)
	for k in count:
		var c: Creature = Mimic.new() if _id == &"mimic" else LevelPopulator.SPECIES[_id].new()
		c.pos = spot.pos if k == 0 else level.field.resolve_circle(spot.pos + Vector2(2.5 * k, 1.0 - k), 1.0)
		if spot.has("normal"):
			c.set(&"wall_normal", spot.normal)
		level.add_entity(c)
		_crits.append(c)
	place_sub(_sub_spot(spot.pos), 1.0)
	_start_filming()


## A guardian in its lair, the sub waiting at the lair's edge.
func _stage_guardian(run_seed: int) -> void:
	stage(GUARDIANS[_id], run_seed, &"lantern", false)
	var g: Guardian = level.guardian
	_crits.append(g)
	_distance = maxf(_distance, 30.0)
	var at := g.lair_center + Vector2(-g.lair_radius.x * 0.8, g.lair_radius.y * 0.2)
	place_sub(level.field.resolve_circle(at, 2.0), 1.0)
	_start_filming()


func _start_filming() -> void:
	sub.lamp_on = false
	_cam = Camera3D.new()
	_cam.fov = 42.0
	_cam.near = 0.5
	_cam.far = 160.0
	add_child(_cam)
	_cam.current = true
	_frame_camera(1.0)
	add_child(PostFx.new())
	shot_prefix = "f"
	for i in int(LENGTH * FPS):
		shot_times.append(0.5 + i / FPS)
	_log = FileAccess.open(_out.path_join("log.csv"), FileAccess.WRITE)
	_log.store_line("t,k,x,y,vx,vy,bx,by,bz,facing,state,swim_clock,swim_power,gait,gait_amp,sub_x,sub_y,pulse")


## The first zone whose biome has [param id] in it.
static func _zone_for(id: StringName) -> int:
	if id == &"mimic":
		return 2
	for z in BiomeLibrary.TOTAL_ZONES:
		if BiomeLibrary.biome_for_zone(z).creatures.has(id) and not BiomeLibrary.is_lair(z):
			return z
	return 0


## Open water some way off from [param at], for the sub to wait in.
func _sub_spot(at: Vector2) -> Vector2:
	for r: float in [16.0, 13.0, 10.0]:
		for k in 16:
			var p := at + Vector2.from_angle(TAU * k / 16.0 + 0.3) * r
			if level.field.sample(p) > 3.0 and level.field.line_of_sight(p, at):
				return p
	return level.field.resolve_circle(at + Vector2(12.0, 0.0), 2.0)


func _focus() -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for c in _crits:
		if is_instance_valid(c) and c.alive:
			sum += c.pos
			n += 1
	return sum / n if n > 0 else sub.pos


func _frame_camera(ease: float) -> void:
	var f := _focus()
	var want := Vector3(f.x, f.y, _distance)
	_cam.position = _cam.position.lerp(want, ease) if _cam.position != Vector3.ZERO else want
	_cam.look_at(Vector3(_cam.position.x, _cam.position.y, 0.0), Vector3.UP)


func direct(dt: float) -> void:
	sub.run.hull = sub.stats.max_hull
	sub.run.battery = sub.stats.max_battery
	var f := _focus()
	var to := f - sub.pos
	if t < 4.0:
		sub.lamp_on = false
	elif t < 10.0:
		sub.lamp_on = true
		sub.aim = to.normalized()
		if to.length() > 6.0:
			sub.external_move = to.normalized() * 0.6
		if not _pinged and t > 5.0:
			_pinged = true
			sub.sonar_cooldown = 0.0
			sub.try_ping()
	else:
		sub.aim = to.normalized()
		sub.external_move = -to.normalized() * 0.8
	_frame_camera(1.0 - exp(-4.0 * dt))
	for k in _crits.size():
		var c := _crits[k]
		if not is_instance_valid(c) or not c.alive:
			continue
		var body := (c.model.global_transform.basis.x if c.model else Vector3.RIGHT).normalized()
		var state: Variant = c.get(&"state")
		_log.store_line("%.3f,%d,%.3f,%.3f,%.3f,%.3f,%.4f,%.4f,%.4f,%.4f,%s,%.4f,%.4f,%.4f,%.4f,%.3f,%.3f,%.4f" % [t, k,
			c.pos.x, c.pos.y, c.vel.x, c.vel.y, body.x, body.y, body.z,
			c.facing.angle(), str(state) if state != null else "", float(c.get(&"_swim_clock")),
			float(c.get(&"_swim_power")), float(c.get(&"_gait")) if c.get(&"_gait") != null else 0.0,
			float(c.get(&"_gait_amp")) if c.get(&"_gait_amp") != null else 0.0, sub.pos.x, sub.pos.y,
			float(c.get(&"_pulse_t")) if c.get(&"_pulse_t") != null else 0.0])
	if shot_times.size() == 1:
		_log.flush()
