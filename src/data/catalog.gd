class_name Catalog
extends RefCounted
## Definitions of submarine frames, hangar upgrades and run modules.
## Effects are expressed as callables that modify a [SubStats].

class FrameDef:
	var id: StringName
	var name: String
	var description: String
	## The zone its derelict lies in, to be found before it can be flown
	## (-1 = in the hangar from the start; see [DerelictFrame]).
	var found_in: int
	var hull_color: Color
	var apply: Callable

	func _init(i: StringName, n: String, d: String, zone: int, color: Color, fx: Callable) -> void:
		id = i
		name = n
		description = d
		found_in = zone
		hull_color = color
		apply = fx


class UpgradeDef:
	var id: StringName
	var name: String
	var description: String
	var costs: PackedInt32Array
	## func(stats: SubStats, level: int)
	var apply: Callable

	func _init(i: StringName, n: String, d: String, c: PackedInt32Array, fx: Callable) -> void:
		id = i
		name = n
		description = d
		costs = c
		apply = fx

	func max_level() -> int:
		return costs.size()


class ModuleDef:
	var id: StringName
	var name: String
	var description: String
	## 0 common, 1 uncommon, 2 rare.
	var rarity: int
	var max_stacks: int
	var color: Color
	## Tool the module requires to be useful, if any.
	var requires_tool: StringName
	var apply: Callable

	func _init(i: StringName, n: String, d: String, r: int, stacks: int, c: Color, fx: Callable,
			req: StringName = &"") -> void:
		id = i
		name = n
		description = d
		rarity = r
		max_stacks = stacks
		color = c
		apply = fx
		requires_tool = req


const RARITY_NAMES: PackedStringArray = ["Common", "Uncommon", "Rare"]
const RARITY_COLORS: Array[Color] = [Color(0.7, 0.85, 0.9), Color(0.4, 1.0, 0.6), Color(1.0, 0.7, 0.25)]
const TOOL_NAMES: Dictionary[StringName, String] = {
	&"flare": "Flare", &"torpedo": "Torpedo", &"shock": "Shock Pulse", &"decoy": "Decoy",
}

## Modules that install a tool; only offered to subs that lack it. A sub
## starts a dive with only its frame's own tools; every other tool is one of
## these cards, found during the run.
const KIT_TOOLS: Dictionary[StringName, StringName] = {
	&"flare_kit": &"flare", &"torpedo_kit": &"torpedo", &"decoy_kit": &"decoy", &"shock_kit": &"shock",
}
## Hangar upgrades that once unlocked a tool on every frame, with what each
## level cost, so a save that bought them gets the salvage back.
const RETIRED_UPGRADES: Dictionary[String, Array] = {
	"flares": [110, 200], "torpedoes": [190, 325], "shock": [225, 350], "decoys": [150, 275],
}

static var _frames: Array[FrameDef] = []
static var _upgrades: Array[UpgradeDef] = []
static var _modules: Array[ModuleDef] = []


static func frames() -> Array[FrameDef]:
	if _frames.is_empty():
		_build_frames()
	return _frames


static func frame(id: StringName) -> FrameDef:
	for f in frames():
		if f.id == id:
			return f
	return null


static func upgrades() -> Array[UpgradeDef]:
	if _upgrades.is_empty():
		_build_upgrades()
	return _upgrades


static func upgrade(id: StringName) -> UpgradeDef:
	for u in upgrades():
		if u.id == id:
			return u
	return null


static func modules() -> Array[ModuleDef]:
	if _modules.is_empty():
		_build_modules()
	return _modules


static func module(id: StringName) -> ModuleDef:
	for m in modules():
		if m.id == id:
			return m
	return null


## Draws [param count] distinct modules weighted by rarity, skipping ones
## that reached their stack limit, are [param locked] (not yet researched) or
## need a tool the submarine lacks.
static func draft(rng: RandomNumberGenerator, owned: Array[StringName], stats: SubStats,
		count := 3, locked: Array[StringName] = []) -> Array[ModuleDef]:
	var pool: Array[ModuleDef] = []
	var weights := PackedFloat32Array()
	for m in modules():
		if owned.count(m.id) >= m.max_stacks or locked.has(m.id):
			continue
		if m.requires_tool != &"" and not stats.has_tool(m.requires_tool):
			continue
		if KIT_TOOLS.has(m.id) and stats.has_tool(KIT_TOOLS[m.id]):
			continue
		pool.append(m)
		weights.append([1.0, 0.55, 0.22][m.rarity])
	var out: Array[ModuleDef] = []
	while out.size() < count and not pool.is_empty():
		var idx := rng.rand_weighted(weights)
		out.append(pool[idx])
		pool.remove_at(idx)
		weights.remove_at(idx)
	return out


static func _build_frames() -> void:
	_frames = [
		FrameDef.new(&"lantern", "Lantern",
			"Balanced research submersible. Bright lamp, a flare launcher and a forgiving hull.",
			-1, Color(1.0, 0.62, 0.12), func(s: SubStats) -> void:
				s.add_tool(&"flare")
				s.flare_capacity = 4),
		FrameDef.new(&"mako", "Mako",
			"A racing hull with a torpedo bay. Fast, hard-hitting and fragile.",
			2, Color(0.85, 0.15, 0.2), func(s: SubStats) -> void:
				s.max_hull = 75.0
				s.max_speed *= 1.22
				s.thrust *= 1.3
				s.boost_drain *= 0.7
				s.harpoon_damage *= 1.35
				s.add_tool(&"torpedo")
				s.torpedo_capacity = 3),
		FrameDef.new(&"bathysphere", "Bathysphere",
			"A slow armored sphere with a huge battery, long sonar and a shock emitter.",
			4, Color(0.3, 0.75, 0.9), func(s: SubStats) -> void:
				s.max_hull = 160.0
				s.max_battery = 145.0
				s.max_speed *= 0.82
				s.thrust *= 0.8
				s.sonar_range *= 1.3
				s.add_tool(&"shock")
				s.add_tool(&"flare")
				s.flare_capacity = 2),
		FrameDef.new(&"whisper", "Whisper",
			"A silent stealth drone. Almost no engine noise, a narrow lamp, quick scanners and sonar decoys.",
			6, Color(0.55, 0.5, 0.95), func(s: SubStats) -> void:
				s.max_hull = 85.0
				s.noise_mult = 0.4
				s.lamp_angle *= 0.75
				s.lamp_range *= 1.15
				s.scan_speed = 1.8
				s.sonar_cost *= 0.6
				s.add_tool(&"decoy")
				s.decoy_capacity = 3
				s.add_tool(&"flare")
				s.flare_capacity = 3),
	]


static func _build_upgrades() -> void:
	_upgrades = [
		UpgradeDef.new(&"hull", "Hull Plating", "+20 maximum hull integrity per level.",
			PackedInt32Array([75, 165, 300, 475, 700]), func(s: SubStats, l: int) -> void:
				s.max_hull += 20.0 * l),
		UpgradeDef.new(&"battery", "Battery Cells", "+20 battery capacity per level.",
			PackedInt32Array([65, 140, 250, 400, 600]), func(s: SubStats, l: int) -> void:
				s.max_battery += 20.0 * l),
		UpgradeDef.new(&"thrusters", "Thrusters", "+7% speed and acceleration per level.",
			PackedInt32Array([90, 190, 340, 525]), func(s: SubStats, l: int) -> void:
				s.max_speed *= 1.0 + 0.07 * l
				s.thrust *= 1.0 + 0.07 * l),
		UpgradeDef.new(&"lamp", "Lamp Optics", "+12% lamp range and -15% lamp drain per level.",
			PackedInt32Array([65, 150, 290]), func(s: SubStats, l: int) -> void:
				s.lamp_range *= 1.0 + 0.12 * l
				s.lamp_drain *= 1.0 - 0.15 * l),
		UpgradeDef.new(&"sonar", "Sonar Array", "+15% sonar range and -10% cooldown per level.",
			PackedInt32Array([75, 175, 325]), func(s: SubStats, l: int) -> void:
				s.sonar_range *= 1.0 + 0.15 * l
				s.sonar_cooldown *= 1.0 - 0.1 * l),
		UpgradeDef.new(&"harpoon", "Harpoon", "+20% harpoon damage and range per level.",
			PackedInt32Array([75, 175, 325]), func(s: SubStats, l: int) -> void:
				s.harpoon_damage *= 1.0 + 0.2 * l
				s.harpoon_range *= 1.0 + 0.1 * l),
		UpgradeDef.new(&"magnet", "Salvage Magnet", "+40% pickup radius per level.",
			PackedInt32Array([50, 125, 250]), func(s: SubStats, l: int) -> void:
				s.pickup_radius *= 1.0 + 0.4 * l),
		UpgradeDef.new(&"insurance", "Salvage Insurance", "Bank 10% more of your salvage when you lose the sub.",
			PackedInt32Array([100, 225, 400]), func(s: SubStats, l: int) -> void:
				s.insurance += 0.1 * l),
	]


static func _build_modules() -> void:
	var hull := Color(1.0, 0.55, 0.3)
	var power := Color(1.0, 0.9, 0.3)
	var light := Color(1.0, 1.0, 0.8)
	var sonar := Color(0.3, 0.95, 1.0)
	var weapon := Color(1.0, 0.35, 0.35)
	var util := Color(0.6, 1.0, 0.6)
	_modules = [
		ModuleDef.new(&"plating", "Reinforced Plating", "+25 max hull.", 0, 4, hull,
			func(s: SubStats) -> void: s.max_hull += 25.0),
		ModuleDef.new(&"capacitor", "Capacitor Bank", "+30 max battery.", 0, 4, power,
			func(s: SubStats) -> void: s.max_battery += 30.0),
		ModuleDef.new(&"cold_lamp", "Cold-Light Lamp", "Lamp drains 40% less battery.", 0, 2, light,
			func(s: SubStats) -> void: s.lamp_drain *= 0.6),
		ModuleDef.new(&"wide_lens", "Wide-Angle Lens", "Lamp cone +30% wider.", 0, 2, light,
			func(s: SubStats) -> void: s.lamp_angle *= 1.3),
		ModuleDef.new(&"long_lamp", "Halogen Core", "Lamp reaches 35% further.", 0, 2, light,
			func(s: SubStats) -> void: s.lamp_range *= 1.35),
		ModuleDef.new(&"amplifier", "Pulse Amplifier", "Sonar range +40%.", 0, 3, sonar,
			func(s: SubStats) -> void: s.sonar_range *= 1.4),
		ModuleDef.new(&"quick_ping", "Quick Ping", "Sonar cooldown and cost -30%.", 0, 2, sonar,
			func(s: SubStats) -> void:
				s.sonar_cooldown *= 0.7
				s.sonar_cost *= 0.7),
		ModuleDef.new(&"echo_analyzer", "Echo Analyzer", "Sonar marks last twice as long and scan 50% faster.", 1, 1, sonar,
			func(s: SubStats) -> void:
				s.sonar_mark_time *= 2.0
				s.scan_speed *= 1.5),
		ModuleDef.new(&"sonar_stun", "Concussive Ping", "Your ping stuns creatures within 14 m.", 2, 1, sonar,
			func(s: SubStats) -> void: s.sonar_stun = true),
		ModuleDef.new(&"silent_screws", "Silent Screws", "Engine noise -35%.", 0, 2, util,
			func(s: SubStats) -> void: s.noise_mult *= 0.65),
		ModuleDef.new(&"hydrofoil", "Hydrodynamic Hull", "+12% speed and acceleration.", 0, 3, util,
			func(s: SubStats) -> void:
				s.max_speed *= 1.12
				s.thrust *= 1.12),
		ModuleDef.new(&"overdrive", "Overdrive", "Boost is 25% faster and drains 25% less.", 1, 2, power,
			func(s: SubStats) -> void:
				s.boost_mult *= 1.25
				s.boost_drain *= 0.75),
		ModuleDef.new(&"serrated", "Serrated Harpoon", "Harpoon damage +50%.", 0, 3, weapon,
			func(s: SubStats) -> void: s.harpoon_damage *= 1.5),
		ModuleDef.new(&"twin_reel", "Twin Reel", "Harpoon range +25% and reels 50% faster.", 0, 2, weapon,
			func(s: SubStats) -> void:
				s.harpoon_range *= 1.25
				s.harpoon_reel *= 1.5),
		ModuleDef.new(&"leech", "Galvanic Barb", "Harpoon hits on creatures recharge 6 battery.", 1, 2, power,
			func(s: SubStats) -> void: s.harpoon_leech += 6.0),
		ModuleDef.new(&"magnet_coil", "Magnet Coil", "Pickup radius doubled.", 0, 2, util,
			func(s: SubStats) -> void: s.pickup_radius *= 2.0),
		ModuleDef.new(&"scavenger", "Scavenger Protocol", "+30% salvage from every pickup.", 1, 3, util,
			func(s: SubStats) -> void: s.salvage_mult += 0.3),
		ModuleDef.new(&"bioconverter", "Bio-Converter", "Glow bulbs restore 60% more battery.", 0, 2, power,
			func(s: SubStats) -> void: s.bulb_mult *= 1.6),
		ModuleDef.new(&"nanites", "Repair Nanites", "Slowly repair the hull when undamaged for a few seconds.", 1, 2, hull,
			func(s: SubStats) -> void: s.regen += 0.8),
		ModuleDef.new(&"shock_hull", "Galvanic Hull", "Creatures touching the hull take shock damage.", 1, 2, weapon,
			func(s: SubStats) -> void: s.contact_zap += 14.0),
		ModuleDef.new(&"ink", "Ink Sac", "Taking damage releases ink that blinds nearby creatures.", 1, 1, util,
			func(s: SubStats) -> void: s.ink_cloud = true),
		ModuleDef.new(&"compass", "Pressure Compass", "Always shows the direction of the descent.", 0, 1, sonar,
			func(s: SubStats) -> void: s.always_compass = true),
		ModuleDef.new(&"lucky", "Deep Pockets", "Caches hold an extra item.", 1, 2, util,
			func(s: SubStats) -> void: s.cache_bonus += 1),
		ModuleDef.new(&"glass_cannon", "Glass Cannon", "+80% harpoon and torpedo damage, -25 max hull.", 2, 1, weapon,
			func(s: SubStats) -> void:
				s.harpoon_damage *= 1.8
				s.torpedo_damage *= 1.8
				s.max_hull -= 25.0),
		ModuleDef.new(&"torpedo_rack", "Torpedo Rack", "+2 torpedoes.", 0, 3, weapon,
			func(s: SubStats) -> void: s.torpedo_capacity += 2, &"torpedo"),
		ModuleDef.new(&"warhead", "Shaped Warhead", "Torpedo damage +50%.", 1, 2, weapon,
			func(s: SubStats) -> void: s.torpedo_damage *= 1.5, &"torpedo"),
		ModuleDef.new(&"flare_pouch", "Flare Pouch", "+3 flares.", 0, 3, light,
			func(s: SubStats) -> void: s.flare_capacity += 3, &"flare"),
		ModuleDef.new(&"capacitor_coil", "Arc Coil", "Shock pulse radius +40% and damage +50%.", 1, 2, weapon,
			func(s: SubStats) -> void:
				s.shock_radius *= 1.4
				s.shock_damage *= 1.5, &"shock"),
		ModuleDef.new(&"flare_kit", "Emergency Flares", "Adds a flare launcher with 3 flares.", 1, 1, light,
			func(s: SubStats) -> void:
				s.add_tool(&"flare")
				s.flare_capacity += 3),
		ModuleDef.new(&"decoy_rack", "Decoy Rack", "+2 decoys.", 0, 3, sonar,
			func(s: SubStats) -> void: s.decoy_capacity += 2, &"decoy"),
		ModuleDef.new(&"decoy_kit", "Sonar Decoys", "Adds a decoy launcher with 2 decoys.", 1, 1, sonar,
			func(s: SubStats) -> void:
				s.add_tool(&"decoy")
				s.decoy_capacity += 2),
		ModuleDef.new(&"torpedo_kit", "Salvaged Torpedo Tube", "Adds a torpedo tube with 2 torpedoes.", 2, 1, weapon,
			func(s: SubStats) -> void:
				s.add_tool(&"torpedo")
				s.torpedo_capacity += 2),
		ModuleDef.new(&"shock_kit", "Salvaged Shock Emitter", "Adds a shock pulse emitter.", 2, 1, weapon,
			func(s: SubStats) -> void: s.add_tool(&"shock")),
	]
