class_name SubEquipmentBase
extends RefCounted
## What every piece of a submarine's kit is built with (see SubEquipment):
## the card colours, the materials, the mount rows and the small helpers that
## place meshes in a mount's frame (Y out of the hull, X towards the bow).

const HULL := Color(1.0, 0.55, 0.3)
const POWER := Color(1.0, 0.9, 0.3)
const LIGHT := Color(1.0, 1.0, 0.8)
const SONAR := Color(0.3, 0.95, 1.0)
const WEAPON := Color(1.0, 0.35, 0.35)
const UTIL := Color(0.6, 1.0, 0.6)

var m: SubmarineModel
var root: Node3D
## The frame's own tools, before any card.
var tools: Array[StringName]
var modules: Array[StringName]
var mats := {}
## Free mount points left in each row, taken front to back.
var _free := {}


func _materials() -> void:
	mats = {
		"paint": m.paint_material(false),
		"metal": m.metal_material(Color(0.085, 0.09, 0.095), 0.6, 0.45, true),
		"steel": m.metal_material(Color(0.78, 0.79, 0.8), 0.95, 0.2, false),
		"brass": m.metal_material(Color(0.76, 0.56, 0.27), 1.0, 0.32, false),
		"copper": m.metal_material(Color(0.86, 0.45, 0.27), 1.0, 0.28, false),
		"rubber": m.metal_material(Color(0.03, 0.03, 0.033), 0.0, 0.85, false),
		"ceramic": m.metal_material(Color(0.9, 0.89, 0.84), 0.0, 0.18, false),
		"iron": m.metal_material(Color(0.2, 0.2, 0.21), 0.75, 0.55, true),
		"olive": m.metal_material(Color(0.2, 0.235, 0.16), 0.25, 0.6, true),
		"safety": m.metal_material(Color(0.95, 0.32, 0.04), 0.1, 0.45, true),
		"canister": m.metal_material(Color(0.98, 0.62, 0.08), 0.15, 0.4, true),
		"warhead": m.metal_material(Color(0.95, 0.72, 0.08), 0.2, 0.4, true),
		"crate": m.metal_material(Color(0.46, 0.4, 0.28), 0.0, 0.8, true),
		"ink": m.metal_material(Color(0.03, 0.025, 0.04), 0.2, 0.08, false),
		"canvas": m.metal_material(Color(0.25, 0.25, 0.18), 0.0, 0.95, false),
		"flare_red": m.metal_material(Color(0.7, 0.07, 0.05), 0.0, 0.45, false),
		"glass": m.glass_material(),
		"lens": MeshKit.emissive_material(Color(1.0, 0.94, 0.78), 6.0),
		"lens_cold": MeshKit.emissive_material(Color(0.75, 0.9, 1.0), 6.0),
		"flare_glow": MeshKit.emissive_material(Color(1.0, 0.3, 0.2), 2.5),
		"bio": MeshKit.emissive_material(Color(0.35, 1.0, 0.45), 2.5),
		"boost": MeshKit.emissive_material(Color(1.0, 0.55, 0.2), 2.5),
		"arc": MeshKit.emissive_material(Color(0.45, 0.85, 1.0), 3.0),
		"beacon": MeshKit.emissive_material(Color(1.0, 0.6, 0.1), 5.0),
		"cockpit_sonar": MeshKit.emissive_material(Color(0.25, 0.9, 0.8), 2.2),
	}
	for c: Color in [HULL, POWER, LIGHT, SONAR, WEAPON, UTIL]:
		mats[c.to_html()] = MeshKit.emissive_material(c, 3.0)


# --- Helpers -------------------------------------------------------------------------

func _n(id: StringName) -> int:
	return modules.count(id)


func _mount(id: StringName) -> Variant:
	return m.mounts.get(id)


## The next free mount in [param row], or null when the row is full.
func _take(row: StringName) -> Variant:
	var free: Array = _free.get(row, [])
	return free.pop_front() if not free.is_empty() else null


## Takes a pair of mounts (near and far side) from [param row].
func _take_pair(row: StringName) -> Array:
	var a: Variant = _take(row)
	var b: Variant = _take(row)
	var out: Array = []
	for t: Variant in [a, b]:
		if t != null:
			out.append(t)
	return out


## Adds [param mesh] at [param local] in [param mount]'s frame.
func _put(mesh: Mesh, mat: String, mount: Transform3D, local := Transform3D.IDENTITY,
		parent: Node3D = null) -> MeshInstance3D:
	return m.place_xform(mesh, mats[mat], mount * local, parent if parent else root)


## A small light in a card's colour.
func _led(mount: Transform3D, at: Vector3, color: Color, size := 0.012, parent: Node3D = null) -> void:
	_put(HullMesh.lathe(_ball(size, 6), 8, 0.0), color.to_html(), mount, Transform3D(Basis(), at), parent)


static func _at(pos: Vector3, rot_deg := Vector3.ZERO) -> Transform3D:
	return Transform3D(Basis.from_euler(rot_deg * PI / 180.0), pos)


## Stands along Y (a lathe built along X), at [param pos].
static func _stand(pos: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3.BACK, PI * 0.5), pos)


## Which way along the mount's Z is down (towards the keel).
static func _down(mount: Transform3D) -> float:
	return 1.0 if mount.basis.z.y < 0.0 else -1.0


# --- Profiles ------------------------------------------------------------------------

static func _ball(r: float, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in steps + 1:
		var a := PI * k / steps
		out.append(Vector2(-cos(a) * r, sin(a) * r + 0.0002))
	return out


static func _cap(r: float, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in steps + 1:
		var a := PI * 0.5 * k / steps
		out.append(Vector2(sin(a) * r, cos(a) * r + 0.0002))
	return out


static func _torus(r: float, tube: float, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in steps + 1:
		var a := TAU * k / steps
		out.append(Vector2(sin(a) * tube, r + cos(a) * tube))
	return out
