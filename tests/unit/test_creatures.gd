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


## A gulper's body stays one smooth curve through a whole strike, whichever
## way it strikes: no section turns sharply from the last, none bends
## suddenly more than its neighbours (a kink), and none stretches apart.
func test_gulper_body_never_kinks() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var layout := LevelGenerator.new().generate(BiomeLibrary.get_biome(2), 5, 4)
	var level := Level.new()
	tree.root.add_child(level)
	level.build(layout, 0)
	var mid := layout.size() * 0.5
	var floor: LevelLayout.Anchor = null
	for a in layout.anchors:
		if a.normal.y < 0.8 or level.field.sample(a.pos + a.normal * 6.0) < 4.0:
			continue
		if floor == null or a.pos.distance_to(mid) < floor.pos.distance_to(mid):
			floor = a
	for dir: Vector2 in [Vector2(0.0, 1.0), Vector2(0.7, 0.7), Vector2(-0.9, 0.4), Vector2(1.0, 0.1)]:
		var g := Gulper.new()
		g.pos = floor.pos + floor.normal * 0.6
		g.wall_normal = floor.normal
		level.add_entity(g)
		var worst := 0.0
		var sudden := 0.0
		var longest := 0.0
		for f in 300:
			if f == 60:
				g.state = Gulper.State.WINDUP
				g.set(&"_timer", Gulper.WINDUP_TIME)
				g.set(&"_strike_from", g.pos)
				g.set(&"_coil_from", g.facing)
				g.set(&"_strike_to", g.pos + dir.normalized() * 8.0)
			g.tick(1.0 / 60.0)
			var p := g.drawn
			var bends := PackedFloat32Array()
			for i in range(1, p.size() - 1):
				longest = maxf(longest, p[i + 1].distance_to(p[i]))
				bends.append(rad_to_deg((p[i] - p[i - 1]).angle_to(p[i + 1] - p[i])))
			for i in bends.size():
				worst = maxf(worst, bends[i])
				if i > 0 and i < bends.size() - 1:
					sudden = maxf(sudden, bends[i] - (bends[i - 1] + bends[i + 1]) * 0.5)
		print("  gulper strike %s: sharpest bend %.1f deg/section, sudden %.1f, longest section %.2f m" % [
			dir, worst, sudden, longest])
		check(worst < 30.0, "strike %s: no sharp bends (%.1f deg)" % [dir, worst])
		check(sudden < 15.0, "strike %s: no kinks (%.1f deg)" % [dir, sudden])
		check(longest < 0.45, "strike %s: no gaps (%.2f m)" % [dir, longest])
		level.entities.erase(g)
		g.free()
	level.free()


func _nearest_anchor(layout: LevelLayout, p: Vector2) -> LevelLayout.Anchor:
	var best: LevelLayout.Anchor = layout.anchors[0]
	for a in layout.anchors:
		if a.pos.distance_to(p) < best.pos.distance_to(p) and a.pos.distance_to(p) > 6.0:
			best = a
	return best
