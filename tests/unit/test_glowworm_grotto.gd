extends TestCase
## The first Midnight Caverns zone has a grotto strung with glow-worms: lit in
## quiet, dark where sound has reached (spreading out from it), and lit again
## a few seconds after the last noise.

const DT := 1.0 / 20.0


func _zone_level(zone: int, run_seed: int) -> Level:
	var run := RunState.new()
	run.run_seed = run_seed
	run.rebuild_stats({})
	run.zone = zone
	var layout := LevelGenerator.new().generate(BiomeLibrary.biome_for_zone(zone), run.zone_seed(zone), zone)
	var level := Level.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(level)
	level.build(layout, 0)
	LevelPopulator.populate(level, run)
	return level


func _grotto(level: Level) -> GlowwormGrotto:
	for e in level.entities:
		if e is GlowwormGrotto:
			return e
	return null


func _run(level: Level, grotto: GlowwormGrotto, seconds: float) -> void:
	for i in int(seconds / DT):
		level.time += DT
		grotto.tick(DT)


func test_strung_from_a_ceiling_in_the_first_midnight_zone() -> void:
	var found := 0
	for run_seed in [3, 17, 42, 99, 2024]:
		var level := _zone_level(4, run_seed)
		var grotto := _grotto(level)
		if grotto:
			found += 1
			check(grotto.worm_pos.size() >= 40, "seed %d: a sky of worms (%d)" % [run_seed, grotto.worm_pos.size()])
			var on_ceiling := 0
			for w in grotto.worm_pos:
				if level.field.sample(Vector2(w.x, w.y + 0.4)) < 0.6:
					on_ceiling += 1
			check(on_ceiling > grotto.worm_pos.size() * 0.8, "seed %d: hanging from the rock" % run_seed)
			check(not LevelPopulator.in_guarded_room(level, grotto.room.center), "seed %d: not in a lair" % run_seed)
		level.free()
	check(found >= 4, "the first Midnight zone has one (%d of 5)" % found)
	for zone in [0, 2, 6]:
		var level := _zone_level(zone, 17)
		check(_grotto(level) == null, "none in zone %d" % zone)
		level.free()


func test_sound_darkens_them_and_quiet_relights_them() -> void:
	var level: Level = null
	var grotto: GlowwormGrotto = null
	for run_seed in [3, 17, 42, 99]:
		level = _zone_level(4, run_seed)
		grotto = _grotto(level)
		if grotto:
			break
		level.free()
	if grotto == null:
		check(false, "a grotto to test with")
		return
	check_near(grotto.brightness(), 1.0, 0.01, "lit in the quiet")
	var w := grotto.worm_pos[grotto.worm_pos.size() / 2]
	var at := Vector2(w.x, w.y - 3.0)
	level.emit_noise(at, 30.0)
	# The dark travels at RIPPLE_SPEED: a worm 3 m off has it after a third of a
	# second, and has dimmed half a second later.
	_run(level, grotto, 0.8)
	var near := -1
	var far := -1
	for i in grotto.worm_pos.size():
		var d := at.distance_to(Vector2(grotto.worm_pos[i].x, grotto.worm_pos[i].y))
		if d < 3.5 and near < 0:
			near = i
		if d > 14.0 and d < 17.0 and far < 0:
			far = i
	check(near >= 0 and grotto.lit[near] < 0.3, "worms by the noise go dark first")
	if far >= 0:
		check(grotto.lit[far] > 0.8, "the dark has not reached the far ones yet")
	_run(level, grotto, 2.0)
	check(grotto.brightness() < 0.6, "the dark spreads")
	_run(level, grotto, GlowwormGrotto.DARK_TIME + 1.0 / GlowwormGrotto.RELIGHT_RATE + 2.0)
	check(grotto.brightness() > 0.95, "quiet again, they light back up")
	level.free()
