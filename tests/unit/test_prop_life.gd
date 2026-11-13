extends TestCase
## The props that answer the sub: shy ones shut fast, stay shut while it
## lingers and open slowly once it has gone; kelp in the hull's way is bent
## the way the sub is going and swings back upright after it has passed.


func _one(at: Vector3) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D(Basis(), at))
	return mm


func _run(life: PropLife, seconds: float, at: Vector2, vel := Vector2.ZERO) -> void:
	for _i in int(seconds * 60.0):
		life.tick(1.0 / 60.0, at, vel)


func test_shy_props_shut_and_open_slowly() -> void:
	var life := PropLife.new()
	var mm := _one(Vector3.ZERO)
	life.add(mm, PropLife.Kind.SHY, [Transform3D()], [Color()])
	_run(life, 1.0, Vector2(20, 0))
	check_eq(life.state_of(mm, 0), 0.0, "open while the sub is far off")
	_run(life, PropLife.SHUT_TIME + 0.1, Vector2(2, 0))
	check_eq(life.state_of(mm, 0), 1.0, "shut quickly when it comes close")
	_run(life, 3.0, Vector2(PropLife.SHY_NEAR + 1.0, 0))
	check_eq(life.state_of(mm, 0), 1.0, "stays shut while it lingers nearby")
	_run(life, PropLife.OPEN_DELAY - 0.3, Vector2(30, 0))
	check_eq(life.state_of(mm, 0), 1.0, "waits a while once it has gone")
	_run(life, 1.0, Vector2(30, 0))
	var opening := life.state_of(mm, 0)
	check(opening > 0.2 and opening < 1.0, "then opens slowly (%.2f)" % opening)
	_run(life, PropLife.OPEN_TIME, Vector2(30, 0))
	check_eq(life.state_of(mm, 0), 0.0, "and is open again")


func test_kelp_is_carried_aside_and_swings_back() -> void:
	var life := PropLife.new()
	var mm := _one(Vector3.ZERO)
	life.add(mm, PropLife.Kind.LEAN, [Transform3D()], [Color()], 6.0)
	_run(life, 0.6, Vector2(0.3, 3.0), Vector2(3, 0))
	check(life.state_of(mm, 0) > 0.3, "bent the way the sub is going (%.2f)" % life.state_of(mm, 0))
	_run(life, 0.6, Vector2(-0.3, 3.0), Vector2(3, 0))
	check(life.state_of(mm, 0) > 0.3, "and not flung back as the hull's middle crosses it")
	var most := 0.0
	for _i in 6:
		_run(life, 0.5, Vector2(20, 3.0))
		most = minf(most, life.state_of(mm, 0))
	check(absf(life.state_of(mm, 0)) < 0.05, "upright again once it has passed (%.3f)" % life.state_of(mm, 0))
	check(most > -0.5, "with no more than a small swing past upright (%.2f)" % most)


func test_far_props_left_alone() -> void:
	var life := PropLife.new()
	var mm := _one(Vector3(100, 0, 0))
	life.add(mm, PropLife.Kind.SHY, [Transform3D(Basis(), Vector3(100, 0, 0))], [Color()])
	_run(life, 1.0, Vector2.ZERO)
	check_eq(life.state_of(mm, 0), 0.0, "a prop out of reach does not stir")
