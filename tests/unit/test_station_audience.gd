extends TestCase
## Over Meridian Deep hangs an audience held by the Choir's tone (log_05):
## still, facing the floor, biting nothing and deaf to sonar; it turns as one
## when the tone shifts. Nothing wakes it: not a shot, not a bump. And the
## tone's pulse hushes the other creatures it passes for a moment.

const DT := 1.0 / 20.0


func _final_level(run_seed := 7) -> Array:
	var zone := BiomeLibrary.TOTAL_ZONES - 1
	var run := RunState.new()
	run.run_seed = run_seed
	run.rebuild_stats({})
	run.refill()
	run.zone = zone
	var layout := LevelGenerator.new().generate(BiomeLibrary.biome_for_zone(zone), run.zone_seed(zone), zone)
	var level := Level.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(level)
	level.build(layout, 0)
	LevelPopulator.populate(level, run)
	return [level, run]


func _audience(level: Level) -> StationAudience:
	for e in level.entities:
		if e is StationAudience:
			return e
	return null


func _with_sub(level: Level, run: RunState, at: Vector2) -> Submarine:
	var sub := Submarine.new()
	level.add_child(sub)
	sub.setup(level, run, at)
	sub.input_enabled = false
	level.player = sub
	return sub


func test_gathered_over_the_station() -> void:
	for run_seed in [7, 99, 1234]:
		var parts := _final_level(run_seed)
		var level: Level = parts[0]
		var audience := _audience(level)
		check(audience != null, "seed %d: the station has its audience" % run_seed)
		if audience:
			check(audience.members.size() >= 5, "seed %d: a crowd of them (%d)" % [run_seed, audience.members.size()])
			for m in audience.members:
				check(m.entranced, "seed %d: held by the tone" % run_seed)
				check(level.field.sample(m.pos) > 1.5, "seed %d: hanging in open water" % run_seed)
		level.free()
	var run := RunState.new()
	run.run_seed = 7
	run.rebuild_stats({})
	var layout := LevelGenerator.new().generate(BiomeLibrary.biome_for_zone(9), run.zone_seed(9), 9)
	var other := Level.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(other)
	other.build(layout, 0)
	LevelPopulator.populate(other, run)
	check(_audience(other) == null, "only at the station")
	other.free()


func test_held_by_the_tone() -> void:
	var parts := _final_level()
	var level: Level = parts[0]
	var audience := _audience(level)
	var lancer: Creature = null
	for m in audience.members:
		if m.species == &"lancer":
			lancer = m
	# Parked near the lancer but clear of every member.
	var at := lancer.pos + Vector2(0.0, 6.0)
	for k in 16:
		var p := lancer.pos + Vector2.from_angle(TAU * k / 16.0) * 6.0
		var clear := level.field.sample(p) > 2.0
		for m in audience.members:
			clear = clear and m.pos.distance_to(p) > m.radius + Submarine.RADIUS + 1.5
		if clear:
			at = p
			break
	var sub := _with_sub(level, parts[1], at)
	var start := lancer.pos
	var hull := sub.run.hull
	# Sonar and engines do not reach it.
	sub.try_ping()
	level.emit_noise(lancer.pos, 40.0)
	for i in 80:
		for m in audience.members:
			m.tick(DT)
	check(lancer.entranced, "a ping does not wake it")
	check(lancer.pos.distance_to(start) < 0.5, "it hangs still (%.2f m)" % lancer.pos.distance_to(start))
	check_eq(sub.run.hull, hull, "it bites nothing")
	# The tone shifts and they turn together.
	var before := audience.turns
	audience.set(&"_tone_in", 0.0)
	audience.tick(DT)
	check_eq(audience.turns, before + 1, "the tone changes")
	# They turn as its pulse rises up through them, the topmost a couple of
	# seconds after the lowest.
	for i in 120:
		for m in audience.members:
			m.tick(DT)
	var focus := audience.focus()
	for m in audience.members:
		if not m.upright:
			check(m.facing.dot((focus - m.pos).normalized()) > 0.9 and m.facing.y < 0.0,
				"they turn as one to where the tone is, facing down to the station")
	# Nothing the sub does wakes them: not a shot...
	var hp := lancer.hp
	check(not lancer.targetable, "no target for the sub's weapons")
	lancer.take_damage(5.0, sub.pos)
	audience.tick(DT)
	check(lancer.entranced and lancer.hp == hp, "hurt, it neither wakes nor is harmed")
	for m in audience.members:
		check(m.entranced, "and none of the rest wakes")
	# ...nor a bump: it slides aside and settles back.
	var home := lancer.pos
	sub.pos = lancer.pos + Vector2(0.4, 0.0)
	for i in 30:
		lancer.tick(DT)
	check(lancer.entranced, "bumped, it stays held")
	check(lancer.pos.distance_to(sub.pos) > lancer.radius + Submarine.RADIUS,
		"and slides aside to let the sub by")
	check_eq(sub.run.hull, hull, "biting nothing")
	sub.pos = at
	for i in 80:
		lancer.tick(DT)
	check(lancer.pos.distance_to(home) < 0.4, "then settles back (%.2f m)" % lancer.pos.distance_to(home))
	var crowd: AudienceCrowd = null
	for c in audience.get_children():
		if c is AudienceCrowd:
			crowd = c
	check(crowd != null and crowd.count() > 100, "a crowd of small fish round them")
	level.free()


func test_a_killed_member_leaves_the_audience() -> void:
	var parts := _final_level(99)
	var level: Level = parts[0]
	var audience := _audience(level)
	var count := audience.members.size()
	var gone: Creature = audience.members[0]
	level.entities.erase(gone)
	gone.free()
	audience.tick(DT)
	check_eq(audience.members.size(), count - 1, "the freed one is dropped, the rest stay")
	level.free()


func test_the_lullaby_is_sung_back() -> void:
	# log_08: Okafor played it a lullaby, and it sang it back.
	var parts := _final_level()
	var level: Level = parts[0]
	var station: MeridianStation = null
	for e in level.entities:
		if e is MeridianStation:
			station = e
	var audience := _audience(level)
	check(station != null and audience != null, "the station and its audience")
	if station == null or audience == null:
		level.free()
		return
	var before := Game.meta.wonders.duplicate()
	Game.meta.wonders.erase("lullaby")
	var sub := _with_sub(level, parts[1], station.pos + Vector2(0.0, 5.0))
	check_eq(station.lullaby_stage, 0, "not before the sub arrives")
	var seen: Array[int] = []
	for i in int(60.0 / DT):
		sub.pos = station.pos + Vector2(0.0, 5.0)
		station.tick(DT)
		if seen.is_empty() or seen[-1] != station.lullaby_stage:
			seen.append(station.lullaby_stage)
		if station.lullaby_stage == 2:
			for m in audience.members:
				if m.entranced:
					check(m.entranced_facing.dot((audience.pos - m.pos).normalized()) > 0.0,
						"the audience turns to listen")
					break
	check_eq(seen, [0, 1, 2, 3] as Array[int], "the speakers play it, then it is sung back from below")
	check(Game.meta.wonders.has("lullaby"), "a wonder")
	Game.meta.wonders = before
	level.free()


func test_the_pulse_hushes_what_it_passes() -> void:
	var parts := _final_level()
	var level: Level = parts[0]
	var audience := _audience(level)
	_with_sub(level, parts[1], audience.pos + Vector2(0.0, -4.0))
	# A hunter out in the gallery, swimming past.
	var lancer: Creature = LevelPopulator.SPECIES[&"lancer"].new()
	lancer.pos = level.field.resolve_circle(audience.pos + Vector2(-12.0, -3.0), 1.0)
	level.add_entity(lancer)
	lancer.vel = Vector2(4.0, 0.0)
	audience.set(&"_tone_in", 0.0)
	audience.tick(DT)
	var deep: Vector2 = audience.get(&"_deep")
	var reach := lancer.pos.distance_to(deep) / Level.ECHO_SPEED
	var t := 0.0
	while t < reach + Level.HUSH_TIME * 0.8:
		lancer.tick(DT)
		level.time += DT
		t += DT
	check(lancer.vel.length() < 1.0, "it stops as the pulse passes (%.2f m/s)" % lancer.vel.length())
	check(lancer.facing.dot((deep - lancer.pos).normalized()) > 0.7, "turned down to the song")
	check(not lancer.entranced, "only for a moment")
	# Not while the Choir is fighting.
	level.boss.active = true
	var other: Creature = LevelPopulator.SPECIES[&"lancer"].new()
	other.pos = lancer.pos + Vector2(2.0, 0.0)
	level.add_entity(other)
	level.choir_wave(deep, 60.0)
	check(other.hush_at == INF, "the Choir's own fight hushes nothing")
	level.boss.active = false
	level.free()

