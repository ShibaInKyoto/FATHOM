extends TestCase
## Data integrity of frames, upgrades and modules.


func test_ids_are_unique() -> void:
	var seen := {}
	for m in Catalog.modules():
		check(not seen.has(m.id), "duplicate module %s" % m.id)
		seen[m.id] = true
	seen.clear()
	for u in Catalog.upgrades():
		check(not seen.has(u.id), "duplicate upgrade %s" % u.id)
		seen[u.id] = true


func test_upgrade_costs_increase() -> void:
	for u in Catalog.upgrades():
		for i in range(1, u.costs.size()):
			check(u.costs[i] > u.costs[i - 1], "%s costs must increase" % u.id)


func test_every_module_applies() -> void:
	for m in Catalog.modules():
		var mods: Array[StringName] = [m.id]
		var stats := SubStats.build(&"lantern", {}, mods)
		check(stats.max_hull > 0.0, "%s leaves a positive hull" % m.id)


func test_draft_is_distinct_and_respects_tools() -> void:
	var rng := RandomNumberGenerator.new()
	var stats := SubStats.build(&"lantern", {}, [])
	for i in 50:
		rng.seed = i
		var picks := Catalog.draft(rng, [], stats, 3)
		check_eq(picks.size(), 3)
		var ids := picks.map(func(m: Catalog.ModuleDef) -> StringName: return m.id)
		for m in picks:
			check(ids.count(m.id) == 1, "draft has duplicates")
			check(m.requires_tool == &"" or stats.has_tool(m.requires_tool), "%s needs a missing tool" % m.id)
			check(m.id != &"flare_kit", "flare kit offered to a sub that already has flares")


func test_draft_offers_only_researched_modules() -> void:
	var rng := RandomNumberGenerator.new()
	var stats := SubStats.build(&"lantern", {}, [])
	var locked := Research.locked_modules(MetaState.new())
	for i in 30:
		rng.seed = i
		for m in Catalog.draft(rng, [], stats, 3, locked):
			check(Research.STARTER_MODULES.has(m.id), "%s offered before it was researched" % m.id)


func test_draft_respects_stack_limits() -> void:
	var rng := RandomNumberGenerator.new()
	var stats := SubStats.build(&"lantern", {}, [])
	var owned: Array[StringName] = [&"compass"]
	for i in 30:
		rng.seed = i
		for m in Catalog.draft(rng, owned, stats, 3):
			check(m.id != &"compass", "maxed module offered again")


func test_frames_have_distinct_stats() -> void:
	var lantern := SubStats.build(&"lantern", {}, [])
	var mako := SubStats.build(&"mako", {}, [])
	var sphere := SubStats.build(&"bathysphere", {}, [])
	check(mako.max_speed > lantern.max_speed)
	check(sphere.max_hull > lantern.max_hull)
	check(mako.has_tool(&"torpedo"))
	check(sphere.has_tool(&"shock"))


func test_tools_come_only_from_the_frame_or_a_kit_card() -> void:
	# Every hangar upgrade maxed out adds no tool a frame lacks.
	var maxed := {}
	for up in Catalog.upgrades():
		maxed[String(up.id)] = up.costs.size()
	for f in Catalog.frames():
		check_eq(SubStats.build(f.id, maxed, []).tools, SubStats.build(f.id, {}, []).tools,
			"%s gets no tool from the hangar" % f.id)
	# Each tool a frame lacks has a kit card, and the card installs it.
	for tool: StringName in Catalog.TOOL_NAMES:
		check(Catalog.KIT_TOOLS.values().has(tool), "%s has a kit card" % tool)
	var lantern := SubStats.build(&"lantern", {}, [&"shock_kit"])
	check(lantern.has_tool(&"shock"), "the shock kit card fits an emitter")


func test_shock_kit_is_offered_only_without_a_shock() -> void:
	var rng := RandomNumberGenerator.new()
	var sphere := SubStats.build(&"bathysphere", {}, [])
	var lantern := SubStats.build(&"lantern", {}, [])
	var saw_kit := false
	for i in 200:
		rng.seed = i
		for m in Catalog.draft(rng, [], sphere, 3):
			check(m.id != &"shock_kit", "the Bathysphere already has a shock emitter")
		for m in Catalog.draft(rng, [], lantern, 3):
			saw_kit = saw_kit or m.id == &"shock_kit"
	check(saw_kit, "the Lantern can be offered the shock kit")
