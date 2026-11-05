extends TestCase
## Spawns each species next to the submarine so its aggressive states run,
## and checks it behaves physically (finite, out of rock, harmful if hostile).

const DT := 1.0 / 60.0


func test_each_species_engages() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var scripts: Dictionary = LevelPopulator.SPECIES.duplicate()
	scripts[&"mimic"] = Mimic
	for id: StringName in scripts:
		var zone := 4
		var run := RunState.new()
		run.run_seed = 3
		run.rebuild_stats({})
		run.refill()
		var layout := LevelGenerator.new().generate(BiomeLibrary.biome_for_zone(zone), 11, zone)
		var level := Level.new()
		tree.root.add_child(level)
		level.build(layout, 0)
		var sub := Submarine.new()
		level.add_child(sub)
		var rooms := layout.chambers_of_kind(&"main")
		var room: LevelLayout.Chamber = rooms[0] if not rooms.is_empty() else layout.chambers[0]
		sub.setup(level, run, room.center)
		sub.input_enabled = false
		level.player = sub
		var c: Creature = scripts[id].new()
		var anchor := _nearest_anchor(layout, room.center)
		c.pos = anchor.pos + anchor.normal * 0.6
		c.set(&"wall_normal", anchor.normal)
		level.add_entity(c)
		var start_hull := run.hull
		for i in 600:
			# Wiggle towards the creature loudly to provoke it.
			sub.external_move = (c.pos - sub.pos).normalized() * (1.0 if i % 120 < 80 else -1.0)
			sub.tick(DT)
			level.tick(DT)
			if not c.alive:
				break
			if i % 200 == 0:
				sub.try_ping()
		check(not is_nan(c.pos.x) and not is_nan(c.pos.y), "%s position finite" % id)
		if c.alive and id != &"gulper":
			check(level.field.sample(c.pos) > -0.5, "%s stays out of rock (%.2f)" % [id, level.field.sample(c.pos)])
		if c.is_hostile() and id != &"stalker":
			check(run.hull < start_hull, "%s managed to hurt the sub" % id)
		level.free()


## Swimming: the tail swings far wider than the head, the eyes ride the
## stroke, and a burst of speed kicks the stroke harder before it settles.
func test_swim_stroke() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var layout := LevelGenerator.new().generate(BiomeLibrary.get_biome(2), 5, 4)
	var level := Level.new()
	tree.root.add_child(level)
	level.build(layout, 0)
	var c := Stalker.new()
	c.pos = Vector2(layout.size().x * 0.5, -60.0)
	level.add_entity(c)
	c.lock_facing = true
	var head := 0.0
	var tail := 0.0
	var eye_off := 0.0
	var eye: Node3D = c._riders[0][0]
	var eye_rest: Transform3D = c._riders[0][1]
	for i in 120:
		c.vel = Vector2.RIGHT * 4.0
		c._update_visuals(DT)
		head = maxf(head, absf(c._swum_transform(Transform3D(Basis(), Vector3(3.3, 0, 0))).origin.z))
		tail = maxf(tail, absf(c._swum_transform(Transform3D(Basis(), Vector3(-3.3, 0, 0))).origin.z))
		eye_off = maxf(eye_off, eye.transform.origin.distance_to(eye_rest.origin))
	check(tail > head * 3.0, "tail swings wider than head (%.2f vs %.2f)" % [tail, head])
	check(eye_off > 0.005 and eye_off < 0.3, "eyes ride the stroke (%.3f)" % eye_off)
	var cruise: float = c._swim_power
	for i in 12:
		c.vel = Vector2.RIGHT * 16.0
		c._update_visuals(DT)
	check(c._swim_power > cruise + 0.15, "a burst kicks the stroke (%.2f > %.2f)" % [c._swim_power, cruise])
	for i in 240:
		c.vel = Vector2.RIGHT * 4.0
		c._update_visuals(DT)
	check(absf(c._swim_power - cruise) < 0.1, "the kick dies away (%.2f)" % c._swim_power)
	level.free()


func _nearest_anchor(layout: LevelLayout, p: Vector2) -> LevelLayout.Anchor:
	var best: LevelLayout.Anchor = layout.anchors[0]
	for a in layout.anchors:
		if a.pos.distance_to(p) < best.pos.distance_to(p) and a.pos.distance_to(p) > 6.0:
			best = a
	return best
