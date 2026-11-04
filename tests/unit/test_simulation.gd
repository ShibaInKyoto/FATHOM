extends TestCase
## Simulates every biome headlessly with a scripted submarine so creature
## behaviour, pickups and projectiles run through their code paths.

const STEPS := 900
const DT := 1.0 / 60.0


func test_every_biome_simulates() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for biome_index in BiomeLibrary.BIOME_COUNT:
		var zone := biome_index * BiomeLibrary.ZONES_PER_BIOME + 1
		var run := RunState.new()
		run.run_seed = 99 + zone
		run.frame_id = &"bathysphere"
		run.modules = [&"torpedo_kit", &"flare_kit"]
		run.rebuild_stats({})
		run.refill()
		run.zone = zone
		var layout := LevelGenerator.new().generate(BiomeLibrary.biome_for_zone(zone), run.zone_seed(zone), zone)
		var level := Level.new()
		tree.root.add_child(level)
		level.build(layout, 0)
		LevelPopulator.populate(level, run)
		var sub := Submarine.new()
		level.add_child(sub)
		sub.setup(level, run, layout.start)
		sub.input_enabled = false
		level.player = sub
		var creatures := level.entities.filter(func(e: Entity) -> bool: return e is Creature).size()
		check(creatures > 3, "biome %d spawns creatures (%d)" % [biome_index, creatures])
		var path := layout.main_path
		for i in STEPS:
			var target := path[mini(i / 12, path.size() - 1)]
			sub.external_move = (target - sub.pos).limit_length(1.0)
			sub.aim = sub.external_move.normalized() if sub.external_move.length() > 0.1 else Vector2.RIGHT
			if i % 120 == 0:
				sub.try_ping()
			if i % 90 == 30:
				sub.tools.use(sub.aim)
				sub.tools.cycle()
			if i % 40 == 10:
				sub.harpoon.fire(sub.aim)
			if i % 40 == 25:
				sub.harpoon.release()
			sub.tick(DT)
			level.tick(DT)
			check(not is_nan(sub.pos.x) and not is_nan(sub.pos.y), "submarine position stays finite")
		check(level.field.sample(sub.pos) > 0.0 or not sub.alive, "biome %d: submarine stays out of rock" % biome_index)
		level.free()
