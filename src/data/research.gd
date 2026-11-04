class_name Research
extends RefCounted
## Research projects, bought in the hangar with research. A new pilot's
## relay lockers hold only basic modules and the yard sells only hull,
## battery and thruster upgrades. Each project adds modules to what the
## decompression stops can offer, and opens upgrade lines that salvage then
## buys level by level. Some build on others; some need a specimen of a
## creature scanned first.

## Modules every relay locker can offer from the first dive.
const STARTER_MODULES: Array[StringName] = [&"plating", &"capacitor", &"cold_lamp", &"long_lamp", &"amplifier",
	&"quick_ping", &"serrated", &"magnet_coil", &"bioconverter"]
## Upgrade lines the hangar sells from the start.
const STARTER_UPGRADES: Array[StringName] = [&"hull", &"battery", &"thrusters"]

class Project:
	var id: String
	var name: String
	var description: String
	var cost: int
	## Projects that must be finished first.
	var requires: Array[String] = []
	## A species that must be in the codex first (&"" for none).
	var specimen: StringName = &""
	var modules: Array[StringName] = []
	var upgrades: Array[StringName] = []

static var _all: Array[Project] = []


static func all() -> Array[Project]:
	if _all.is_empty():
		_all = [
			_project("optics", "Optics Lab", "Grind better glass for the lamp.", 40, [], &"",
				[&"wide_lens"], [&"lamp"]),
			_project("echo", "Echo Sounding", "Read more out of every returning ping.", 40, [], &"",
				[&"compass", &"echo_analyzer"], [&"sonar"]),
			_project("harpoon", "Harpoon Workshop", "A heavier reel and a better barb.", 50, [], &"",
				[&"twin_reel"], [&"harpoon"]),
			_project("salvage", "Salvage Logistics", "Pack more into every haul.", 50, [], &"",
				[&"scavenger", &"lucky"], [&"magnet"]),
			_project("underwriting", "Underwriting", "Convince an insurer that you will come back.", 60, [], &"",
				[], [&"insurance"]),
			_project("pyro", "Pyrotechnics", "Flares that burn underwater, and racks to carry them.", 60, [], &"",
				[&"flare_pouch", &"flare_kit"], []),
			_project("propulsion", "Propulsion Lab", "Smoother hulls and hotter motors.", 80, [], &"",
				[&"hydrofoil", &"overdrive"], []),
			_project("bioelectric", "Bio-Electrics", "Learn from the jellies how living things hold a charge.", 80,
				[], &"jelly", [&"leech", &"shock_hull", &"nanites"], []),
			_project("mimicry", "Mimicry Studies", "A cache that bites taught us to lie back.", 80, [], &"mimic",
				[&"ink"], []),
			_project("acoustic", "Acoustic Dampening", "Learn what the Stalker hears, and stop making it.", 90,
				["echo"], &"stalker", [&"silent_screws"], []),
			_project("decoys", "Decoy Systems", "Throw your voice into the dark.", 100, ["acoustic"], &"",
				[&"decoy_rack", &"decoy_kit"], []),
			_project("ordnance", "Ordnance", "Self-propelled harpoons, with a warhead.", 120, ["harpoon"], &"",
				[&"torpedo_rack", &"warhead", &"torpedo_kit"], []),
			_project("voltage", "High Voltage", "The siphonophore's sting, in a capacitor, and an emitter to loose it.",
				140, ["bioelectric"], &"siphon", [&"capacitor_coil", &"shock_kit"], []),
			_project("concussion", "Concussive Sonar", "A ping loud enough to stun.", 160, ["acoustic", "voltage"],
				&"", [&"sonar_stun"], []),
			_project("overclock", "Overclocked Arms", "Strip the safeties off everything that fires.", 180,
				["ordnance"], &"", [&"glass_cannon"], []),
		]
	return _all


static func find(id: String) -> Project:
	for p in all():
		if p.id == id:
			return p
	return null


## Why [param p] cannot be started yet ("" when it can, research aside).
static func blocker(meta: MetaState, p: Project) -> String:
	var missing: Array[String] = []
	for r in p.requires:
		if not meta.projects.has(r):
			missing.append(find(r).name)
	if p.specimen != &"" and not meta.codex.has(String(p.specimen)):
		var entry := CreatureCodex.entry(p.specimen)
		missing.append("a scanned %s" % (entry.name if entry else String(p.specimen)))
	return "" if missing.is_empty() else "Needs " + " and ".join(missing)


## Modules a relay locker may not offer yet.
static func locked_modules(meta: MetaState) -> Array[StringName]:
	var locked: Array[StringName] = []
	for p in all():
		if not meta.projects.has(p.id):
			locked.append_array(p.modules)
	return locked


static func upgrade_open(meta: MetaState, id: StringName) -> bool:
	return STARTER_UPGRADES.has(id) or project_for_upgrade(id) == null \
		or meta.projects.has(project_for_upgrade(id).id)


static func project_for_upgrade(id: StringName) -> Project:
	for p in all():
		if p.upgrades.has(id):
			return p
	return null


## "Unlocks: Lamp Optics upgrades, Wide-Angle Lens"
static func unlocks_text(p: Project) -> String:
	var parts: Array[String] = []
	for u in p.upgrades:
		parts.append("%s upgrades" % Catalog.upgrade(u).name)
	for m in p.modules:
		parts.append(Catalog.module(m).name)
	return "Unlocks: " + ", ".join(parts)


static func _project(id: String, name: String, desc: String, cost: int, requires: Array[String],
		specimen: StringName, modules: Array[StringName], upgrades: Array[StringName]) -> Project:
	var p := Project.new()
	p.id = id
	p.name = name
	p.description = desc
	p.cost = cost
	p.requires = requires
	p.specimen = specimen
	p.modules = modules
	p.upgrades = upgrades
	return p
