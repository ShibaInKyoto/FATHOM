extends TestCase
## The harpoon flies to the end of its line or the first thing it strikes,
## then comes straight home unless the trigger is held; held, it reels a
## cache in until let go. It strikes a creature and pulls free, fires again
## the moment it is home if pressed on the way, goes through the crosshair,
## and lets go of a catch snagged on rock rather than staying hooked.

const DT := 1.0 / 60.0


## Somewhere with at least 5 m of open water all round, searching outwards.
func _open_point(level: Level, near: Vector2) -> Vector2:
	for r in range(0, 60, 3):
		for i in 24:
			var p: Vector2 = near + Vector2.from_angle(TAU * i / 24.0) * r
			if level.field.sample(p) > 5.0:
				return p
	return near


## A level with the sub in open water, aiming right at [param target] 6 m off.
func _stage(target: Entity) -> Array:
	var run := RunState.new()
	run.rebuild_stats({})
	var layout := LevelGenerator.new().generate(BiomeLibrary.biome_for_zone(2), 4242, 2)
	var level := Level.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(level)
	level.build(layout, 0)
	var at := _open_point(level, layout.start)
	var sub := Submarine.new()
	level.add_child(sub)
	sub.setup(level, run, at - Vector2(3.0, 0.0))
	sub.input_enabled = false
	level.player = sub
	if target:
		target.pos = at + Vector2(3.0, 0.0)
		level.add_entity(target)
	sub.aim = Vector2.RIGHT
	return [level, sub]


## Ticks the harpoon (and the sub) until it leaves [param state] or time runs out.
func _tick_while(sub: Submarine, state: Harpoon.State, seconds: float) -> float:
	var t := 0.0
	while t < seconds and sub.harpoon.state == state:
		sub.harpoon.tick(DT)
		t += DT
	return t


func test_strikes_a_creature_and_pulls_free() -> void:
	var fish := Lancer.new()
	var parts := _stage(fish)
	var level: Level = parts[0]
	var sub: Submarine = parts[1]
	fish.max_hp = 1000.0
	fish.hp = 1000.0
	fish.stun(10.0)
	var start := fish.pos.distance_to(sub.pos)
	# Held down the whole time: it still pulls free once the blow lands.
	sub.harpoon.fire(Vector2.RIGHT)
	_tick_while(sub, Harpoon.State.FLYING, 0.5)
	check_eq(sub.harpoon.state, Harpoon.State.ATTACHED, "the barb bites")
	check(fish.hp < 1000.0, "and hurts")
	_tick_while(sub, Harpoon.State.ATTACHED, 1.0)
	check_eq(sub.harpoon.state, Harpoon.State.RETRACTING, "then pulls free and comes home")
	check(fish.pos.distance_to(sub.pos) > start - 1.0, "the creature is not reeled in")
	level.free()


func test_a_tap_flies_out_and_comes_straight_home() -> void:
	var parts := _stage(null)
	var level: Level = parts[0]
	var sub: Submarine = parts[1]
	sub.harpoon.fire(Vector2.RIGHT)
	sub.harpoon.tick(DT)
	sub.harpoon.release()
	check_eq(sub.harpoon.state, Harpoon.State.FLYING, "let go early, it carries on out")
	_tick_while(sub, Harpoon.State.FLYING, 2.0)
	check_eq(sub.harpoon.state, Harpoon.State.RETRACTING, "then turns for home by itself")
	# Pressed again on the way home: it goes straight back out on arrival.
	sub.harpoon.fire(Vector2.RIGHT)
	sub.harpoon.release()
	check_eq(sub.harpoon.state, Harpoon.State.RETRACTING, "not out again before it is back")
	_tick_while(sub, Harpoon.State.RETRACTING, 2.0)
	check_eq(sub.harpoon.state, Harpoon.State.FLYING, "but out again the moment it is, with no wait")
	level.free()


func test_a_tap_glances_off_a_cache() -> void:
	var cache := SalvageCache.new()
	var parts := _stage(cache)
	var level: Level = parts[0]
	var sub: Submarine = parts[1]
	sub.harpoon.throw(Vector2.RIGHT)
	_tick_while(sub, Harpoon.State.FLYING, 0.5)
	check_eq(sub.harpoon.state, Harpoon.State.RETRACTING, "not held, it does not hook the catch")
	level.free()


func test_it_flies_through_the_crosshair() -> void:
	var parts := _stage(null)
	var level: Level = parts[0]
	var sub: Submarine = parts[1]
	sub.aim = Vector2(1.0, 0.4).normalized()
	var mark := sub.aim_point()
	sub.harpoon.fire(sub.aim, true)
	var start := sub.harpoon.tip
	var miss := ((mark - start) - (mark - start).project(sub.harpoon.direction)).length()
	check(miss < 0.01, "the line from the muzzle runs through the crosshair (off by %.3f m)" % miss)
	check(start.distance_to(sub.pos) > 0.1, "from the launcher, off the hull's centre")
	level.free()


func test_holding_reels_a_cache_in() -> void:
	var cache := SalvageCache.new()
	var parts := _stage(cache)
	var level: Level = parts[0]
	var sub: Submarine = parts[1]
	sub.harpoon.fire(Vector2.RIGHT)
	_tick_while(sub, Harpoon.State.FLYING, 0.5)
	check_eq(sub.harpoon.state, Harpoon.State.ATTACHED, "the harpoon hooks the cache")
	var start := cache.pos.distance_to(sub.pos)
	for i in 8:
		sub.harpoon.tick(DT)
		cache.pos += cache.vel * DT
	check(cache.pos.distance_to(sub.pos) < start - 0.3, "held, the catch is reeled towards the sub")
	sub.harpoon.release()
	check_eq(sub.harpoon.state, Harpoon.State.RETRACTING, "let go, the cache is dropped")
	level.free()


func test_lets_go_of_a_snagged_catch() -> void:
	var cache := SalvageCache.new()
	var parts := _stage(cache)
	var level: Level = parts[0]
	var sub: Submarine = parts[1]
	sub.harpoon.fire(Vector2.RIGHT)
	_tick_while(sub, Harpoon.State.FLYING, 0.5)
	var pinned := cache.pos
	var held := 0.0
	while held < 5.0 and sub.harpoon.state == Harpoon.State.ATTACHED:
		sub.harpoon.tick(DT)
		# Snagged: the reel cannot move it.
		cache.pos = pinned
		cache.vel = Vector2.ZERO
		held += DT
	check(sub.harpoon.state != Harpoon.State.ATTACHED, "a catch that will not come is let go")
	check(held < Harpoon.DRAG_STALL + 0.5, "soon after it stops coming (held %.1f s)" % held)
	level.free()


func test_a_thrown_harpoon_comes_home_by_itself() -> void:
	var parts := _stage(null)
	var level: Level = parts[0]
	var sub: Submarine = parts[1]
	sub.harpoon.throw(Vector2.RIGHT)
	_tick_while(sub, Harpoon.State.FLYING, 2.0)
	sub.harpoon.tick(DT)
	check(sub.harpoon.state == Harpoon.State.RETRACTING or sub.harpoon.state == Harpoon.State.IDLE,
		"thrown, it lands and comes home without being let go")
	level.free()
