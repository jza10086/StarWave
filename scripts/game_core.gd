class_name ShmupCore
extends RefCounted
## Pure, deterministic vertical-shooter simulation. Base canvas is 1440 × 960; resizing expands the entire playable canvas.
## The drawing/input layer owns pause and calls step only while the game is active.

const FIELD := Vector2(1440.0, 960.0)
const PLAYER_RADIUS := 4.0
const PLAYER_HIT_RADIUS := PLAYER_RADIUS
const PLAYER_SPEED := 350.0
const FOCUS_SPEED := 155.0
const MAX_BULLETS := 900
const MAX_SHOTS := 220
const MAX_ENEMIES := 50
const MAX_PICKUPS := 60
const MAX_EFFECTS := 90
const MAX_CANCEL_EFFECTS := 384
const MAX_DAMAGE_WAVES := 4
const DAMAGE_WAVE_DURATION := 1.5
const CANCEL_EFFECT_DURATION := 0.5
const BOSS_TIME := 86.0
const CYAN := Color("77e9ff")
const PINK := Color("ff70c8")
const GOLD := Color("ffcd68")
const PURPLE := Color("b7a2ff")

var field_size := FIELD
var player := Vector2(field_size.x * 0.5, field_size.y - 150.0)
var lives: int = 3
var score: int = 0
var bombs: int = 3
var power: int = 1
var state: String = "ready"
var elapsed: float = 0.0
var wave: int = 0
var stage_label: String = "SECTOR 01 · NEON RAIN"
var focused: bool = false
var invulnerable: float = 0.0
var enemies: Array[Dictionary] = []
var bullets: Array[Dictionary] = []
var shots: Array[Dictionary] = []
var pickups: Array[Dictionary] = []
var effects: Array[Dictionary] = []
# Gameplay wave and presentation remnants are separate: remnants NEVER collide.
var damage_waves: Array[Dictionary] = []
var cancel_effects: Array[Dictionary] = []
var _cancel_pool: Array[Dictionary] = []
var _next_damage_wave_id: int = 1
var boss: Dictionary = {}
var graze: int = 0
var kills: int = 0
var bomb_flash: float = 0.0
var shake: float = 0.0
var last_event: String = ""

var _next_id: int = 1
var _shot_timer: float = 0.0
var _next_wave_time: float = 1.8
var _boss_spawned: bool = false
var _bomb_latched: bool = false
var _extra_life_awarded: bool = false

func _init() -> void:
	reset()

## Keep the whole viewport playable without stretching hitboxes or bullet geometry.
## Resize maps positions proportionally, but preserves physical speeds and radii.
func resize_field(size: Vector2) -> void:
	if not size.is_finite() or size.x < FIELD.x or size.y < FIELD.y or size == field_size:
		return
	var ratio := size / field_size
	player *= ratio
	for collection in [enemies, bullets, shots, pickups, effects, damage_waves, cancel_effects]:
		for entity in collection:
			entity["pos"] = Vector2(entity["pos"]) * ratio
			if entity.has("origin_x"):
				entity["origin_x"] = float(entity["origin_x"]) * ratio.x
	if not boss.is_empty():
		boss["pos"] = Vector2(boss["pos"]) * ratio
		for key in ["move_from", "move_to"]:
			if boss.has(key):
				boss[key] = Vector2(boss[key]) * ratio
	field_size = size
	for shield in damage_waves:
		shield["max_radius"] = _damage_wave_extent(shield["pos"])
		shield["radius"] = damage_wave_radius(shield)
		shield["previous_radius"] = shield["radius"]
	player.x = clampf(player.x, 24.0, field_size.x - 24.0)
	player.y = clampf(player.y, 90.0, field_size.y - 34.0)

func reset() -> void:
	player = Vector2(field_size.x * 0.5, field_size.y - 150.0)
	lives = 3
	score = 0
	bombs = 3
	power = 1
	state = "ready"
	elapsed = 0.0
	wave = 0
	stage_label = "SECTOR 01 · NEON RAIN"
	focused = false
	invulnerable = 0.0
	graze = 0
	kills = 0
	bomb_flash = 0.0
	shake = 0.0
	last_event = ""
	enemies.clear()
	bullets.clear()
	shots.clear()
	pickups.clear()
	effects.clear()
	damage_waves.clear()
	for remnant in cancel_effects:
		_cancel_pool.append(remnant)
	cancel_effects.clear()
	_next_damage_wave_id = 1
	boss = {}
	_next_id = 1
	_shot_timer = 0.0
	_next_wave_time = 1.8
	_boss_spawned = false
	_bomb_latched = false
	_extra_life_awarded = false

func start() -> void:
	reset()
	state = "playing"
	invulnerable = 1.8

func step(delta: float, move: Vector2, fire: bool, focus: bool, bomb_pressed: bool) -> void:
	if state != "playing" or not is_finite(delta) or delta < 0.0:
		return
	# Prevent a resumed/window-drag frame from teleporting projectiles or the player.
	var remaining: float = minf(delta, 0.1)
	var direction := move.limit_length(1.0)
	if not direction.is_finite():
		direction = Vector2.ZERO
	focused = focus
	last_event = ""
	if bomb_pressed and not _bomb_latched:
		_use_bomb()
	_bomb_latched = bomb_pressed
	while remaining > 0.000001 and state == "playing":
		var dt: float = minf(remaining, 1.0 / 120.0)
		_step_tick(dt, direction, fire)
		remaining -= dt

func _step_tick(dt: float, move: Vector2, fire: bool) -> void:
	elapsed += dt
	invulnerable = maxf(0.0, invulnerable - dt)
	bomb_flash = maxf(0.0, bomb_flash - dt)
	shake = maxf(0.0, shake - dt * 22.0)
	var speed: float = FOCUS_SPEED if focused else PLAYER_SPEED
	player += move * speed * dt
	player.x = clampf(player.x, 24.0, field_size.x - 24.0)
	player.y = clampf(player.y, 90.0, field_size.y - 34.0)
	_update_stage()
	_shot_timer = maxf(0.0, _shot_timer - dt)
	if fire and _shot_timer <= 0.0:
		_fire_player()
		_shot_timer = 0.095
	_update_enemies(dt)
	if state != "playing":
		return
	_update_boss(dt)
	if state != "playing":
		return
	_update_shots(dt)
	if state != "playing":
		return
	_update_cancel_effects(dt)
	_update_damage_waves(dt)
	_update_bullets(dt)
	if state != "playing":
		return
	_update_pickups(dt)
	_update_effects(dt)
	if not _extra_life_awarded and score >= 25000:
		_extra_life_awarded = true
		lives = mini(lives + 1, 5)
		_add_effect(player, "extend", 80.0, 1.2)
		last_event = "extend"

func _update_stage() -> void:
	if not _boss_spawned and elapsed >= BOSS_TIME:
		_spawn_boss()
	elif not _boss_spawned and elapsed >= _next_wave_time:
		wave += 1
		_spawn_wave(wave)
		_next_wave_time += 8.0
	if not _boss_spawned:
		if elapsed < 26.0:
			stage_label = "SECTOR 01 · NEON RAIN"
		elif elapsed < 58.0:
			stage_label = "SECTOR 02 · CROSSWIND"
		else:
			stage_label = "SECTOR 03 · STORM FRONT"

func _spawn_wave(index: int) -> void:
	# First teach each new silhouette alone, then alternate formations and mixed roles.
	# Eight-second wave spacing and 86-second boss arrival remain unchanged.
	var recipes := [
		["scout", "scout", "scout", "scout", "scout"],
		["sniper"], ["sweeper"], ["orbiter"],
		["sniper", "scout", "sniper"],
		["weaver", "sweeper", "weaver"],
		["orbiter", "gunner"],
		["sniper", "sweeper", "scout"],
		["weaver", "orbiter", "weaver"],
		["sniper", "gunner", "sweeper"],
		["orbiter", "scout", "sniper"]]
	var recipe: Array = recipes[(index - 1) % recipes.size()]
	for i in range(recipe.size()):
		var lane: float = float(i + 1) / float(recipe.size() + 1)
		if recipe.size() == 1:
			lane = 0.32 if recipe[i] == "sniper" else (0.68 if recipe[i] == "sweeper" else 0.38)
		_spawn_enemy(recipe[i], Vector2(field_size.x * lane, -48.0 - i * 48.0), i)

func _spawn_enemy(kind: String, position: Vector2, order: int) -> void:
	if enemies.size() >= MAX_ENEMIES:
		return
	var health: float = 22.0
	var radius: float = 19.0
	var speed: float = 138.0
	if kind == "gunner":
		health = 82.0
		radius = 27.0
		speed = 64.0
	elif kind == "weaver":
		health = 40.0
		radius = 22.0
		speed = 91.0
	elif kind == "sniper":
		health = 65.0
		radius = 24.0
		speed = 150.0
	elif kind == "sweeper":
		health = 100.0
		radius = 28.0
		speed = 145.0
	elif kind == "orbiter":
		health = 115.0
		radius = 29.0
		speed = 150.0
	# All route geometry is normalized once; viewport changes map the complete path.
	var side := -1.0 if (order + wave) % 2 == 0 else 1.0
	if kind == "sweeper" and position.y < 0.0:
		position = Vector2(-65.0 if side < 0.0 else field_size.x + 65.0, 110.0)
	enemies.append({"id": _next_id, "type": kind, "pos": position, "origin_x": position.x,
		"hp": health, "max_hp": health, "radius": radius, "speed": speed,
		"age": 0.0, "timer": 0.08 + order * 0.12, "order": order, "flash": 0.0,
		"route_start": position / field_size, "route_size": field_size, "route_side": side,
		"stage": "enter", "attack_allowed": false, "velocity": Vector2.ZERO, "rotation": 0.0,
		"telegraph": 0.0, "warning_angle": PI * 0.5, "attack_index": 0, "burst_left": 0})
	_next_id += 1

func _update_enemies(dt: float) -> void:
	for i in range(enemies.size() - 1, -1, -1):
		var enemy: Dictionary = enemies[i]
		enemy["age"] += dt
		enemy["flash"] = maxf(0.0, float(enemy["flash"]) - dt)
		var age: float = enemy["age"]
		var kind: String = enemy["type"]
		var exit_at := 5.4 if kind == "sniper" else 6.4
		enemy["stage"] = "enter" if age < 2.1 else ("attack" if age < exit_at else "exit")
		enemy["attack_allowed"] = enemy["stage"] == "attack"
		if kind == "orbiter":
			enemy["attack_allowed"] = (age >= 2.2 and age < 3.9) or (age >= 4.5 and age < 6.3)
		var pos := enemy_route_position(enemy, age)
		var velocity := (enemy_route_position(enemy, age + 0.002) - enemy_route_position(enemy, maxf(0.0, age - 0.002))) / 0.004
		enemy["pos"] = pos
		enemy["velocity"] = velocity
		# Banking follows lateral motion, never spins the symbol upside-down.
		var bank := clampf(-velocity.x / 520.0, -0.30, 0.30)
		enemy["rotation"] = lerpf(float(enemy["rotation"]), bank, 1.0 - exp(-dt * 7.0))
		if age >= 8.8:
			enemies.remove_at(i)
			continue
		if not bool(enemy["attack_allowed"]):
			enemy["telegraph"] = 0.0
			enemy["burst_left"] = 0
		if bool(enemy["attack_allowed"]) and pos.y > 25.0 and pos.y < field_size.y - 210.0:
			if float(enemy["telegraph"]) > 0.0:
				enemy["telegraph"] = maxf(0.0, float(enemy["telegraph"]) - dt)
				if float(enemy["telegraph"]) <= 0.0:
					_enemy_fire(enemy)
			else:
				enemy["timer"] -= dt
				if float(enemy["timer"]) <= 0.0 and age < 7.0:
					# Lock once before the internal wind-up; never track during the pause or burst.
					if int(enemy["burst_left"]) > 0:
						_enemy_fire(enemy)
					else:
						enemy["warning_angle"] = (player - pos).angle()
						if enemy["type"] == "weaver":
							enemy["warning_angle"] = PI * 0.5 + sin(age * 1.5) * 0.55
						elif enemy["type"] == "sweeper":
							enemy["warning_angle"] = PI * 0.5 + sin(age * 0.8) * 0.35
						enemy["telegraph"] = 0.7 if enemy["type"] in ["sniper", "orbiter"] else 0.5
		if invulnerable <= 0.0 and pos.distance_squared_to(player) < pow(float(enemy["radius"]) * 0.7 + PLAYER_RADIUS, 2.0):
			_hit_player()

## Cubic Hermite geometry uses endpoint velocities in logical pixels/second.
## Unlike clamping a moving body to a station, adjacent pieces share the same tangent.
static func _route_segment(a: Vector2, b: Vector2, va: Vector2, vb: Vector2, time: float, duration: float) -> Vector2:
	var u := clampf(time / duration, 0.0, 1.0)
	return a * (2*u*u*u - 3*u*u + 1) + va * duration * (u*u*u - 2*u*u + u) + b * (-2*u*u*u + 3*u*u) + vb * duration * (u*u*u - u*u)

func enemy_route_position(enemy: Dictionary, age: float) -> Vector2:
	return _enemy_route_native(enemy, age) * (field_size / Vector2(enemy["route_size"]))

func _enemy_route_native(enemy: Dictionary, age: float) -> Vector2:
	var route_field: Vector2 = enemy["route_size"]
	var start: Vector2 = Vector2(enemy["route_start"]) * route_field
	var side: float = enemy["route_side"]
	var kind: String = enemy["type"]
	var order: int = enemy["order"]
	var lane := clampf(float(enemy["origin_x"]) / field_size.x, 0.20, 0.80)
	var station := Vector2(route_field.x * lane, 225.0 + order * 24.0)
	if kind == "sweeper":
		var direction := -side
		var a := Vector2(route_field.x * (0.22 if direction > 0 else 0.78), 205.0)
		var b := Vector2(route_field.x * (0.78 if direction > 0 else 0.22), 235.0)
		var flow := Vector2(direction * route_field.x * 0.115, -24.0)
		if age < 2.1: return _route_segment(start, a, Vector2(direction * 100, 35), flow, age, 2.1)
		if age < 6.4: return _route_segment(a, b, flow, flow, age-2.1, 4.3)
		return _route_segment(b, Vector2(route_field.x + 110 if direction > 0 else -110, 125), flow, Vector2(direction*230,-50), age-6.4, 2.4)
	if kind == "orbiter":
		var center := station + Vector2(0, 65)
		var rx := 105.0
		var ry := 65.0
		var omega := side * TAU * 0.75 / 4.3
		var theta := -PI/2 + omega * clampf(age-2.1,0,4.3)
		var entry := center + Vector2(0,-ry)
		var entry_v := Vector2(rx*omega,0)
		if age < 2.1: return _route_segment(start, entry, Vector2(side*65,165), entry_v, age,2.1)
		if age < 6.4: return center + Vector2(cos(theta)*rx,sin(theta)*ry)
		var end := center + Vector2(cos(theta)*rx,sin(theta)*ry)
		var tangent := Vector2(-sin(theta)*rx,cos(theta)*ry)*omega
		return _route_segment(end, end+tangent*2.4+Vector2(side*120,-260), tangent, tangent+Vector2(side*80,-180),age-6.4,2.4)
	if kind == "sniper":
		station.x += side*75
		var drift := Vector2(-side*14,7)
		if age < 2.1: return _route_segment(start,station,Vector2(side*110,210),drift,age,2.1)
		if age < 5.4: return station+drift*(age-2.1)
		var end := station+drift*3.3
		return _route_segment(end,Vector2(-110 if side < 0 else route_field.x+110,-100),drift,Vector2(side*260,-130),age-5.4,3.4)
	# Scouts share mirrored S geometry; their staggered entry height offsets arrival.
	# Gunners/weavers use the same continuous three-stage grammar at different lanes.
	var t := age
	var a := station + Vector2(side*65,0)
	var b := station + Vector2(-side*100,180 if kind == "scout" else 65)
	var flow := Vector2(-side*55,65 if kind == "scout" else 24)
	if t < 2.1: return _route_segment(start,a,Vector2(side*50,170),flow,t,2.1)
	if t < 6.4: return _route_segment(a,b,flow,flow,t-2.1,4.3)
	return _route_segment(b,Vector2(route_field.x+100 if side < 0 else -100,50),flow,Vector2(-side*250,-100),t-6.4,2.4)

func _enemy_fire(enemy: Dictionary) -> void:
	var pos: Vector2 = enemy["pos"]
	# Suppress point-blank emissions and all shots after retreat begins.
	if pos.distance_to(player) < 180.0 or float(enemy["age"]) >= 7.0 or not bool(enemy.get("attack_allowed", true)):
		enemy["timer"] = 0.8
		enemy["burst_left"] = 0
		return
	var aim: float = enemy["warning_angle"]
	match String(enemy["type"]):
		"scout":
			_fan(pos, aim, 3, 0.22, 180.0, PINK, 6.0)
			enemy["timer"] = 1.8
		"gunner":
			# Two slow obstacles define a route; the central medium fan asks for movement.
			_fan(pos, aim, 3, 0.22, 170.0, GOLD, 6.0)
			for side in [-1.0, 1.0]:
				_add_bullet(pos, Vector2.from_angle(aim + side * 0.70) * 95.0, 10.0, GOLD, "crescent", side * 0.16)
			enemy["timer"] = 2.2
		"weaver":
			for side in [-1.0, 1.0]:
				for j in 2:
					_add_bullet(pos, Vector2.from_angle(aim + side * (0.25 + j * 0.20)) * 175.0, 6.0, PURPLE, "orb", side * 0.20)
			enemy["timer"] = 1.65
		"sniper":
			_fan(pos, aim, 3, 0.14, 290.0, GOLD, 3.5, "needle")
			_continue_burst(enemy, 2, 0.25, 2.3)
		"sweeper":
			# Two wings sweep together; the middle lane remains intentionally open.
			var sweep: float = aim + (int(enemy["attack_index"]) % 3 - 1) * 0.12
			_fan(pos, sweep - 0.48, 3, 0.15, 175.0, PINK, 6.0)
			_fan(pos, sweep + 0.48, 3, 0.15, 175.0, PINK, 6.0)
			_continue_burst(enemy, 3, 0.34, 2.1)
		"orbiter":
			_gap_ring(pos, 14, float(enemy["age"]) * 0.2, aim, 0.60, 160.0, PURPLE, 6.0)
			_continue_burst(enemy, 2, 0.45, 2.5)
	enemy["attack_index"] += 1

func _continue_burst(enemy: Dictionary, count: int, spacing: float, rest: float) -> void:
	if int(enemy["burst_left"]) == 0:
		enemy["burst_left"] = count - 1
	else:
		enemy["burst_left"] -= 1
	enemy["timer"] = spacing if int(enemy["burst_left"]) > 0 else rest

func _gap_ring(position: Vector2, count: int, offset: float, gap: float, half_gap: float, speed: float, color: Color, radius: float) -> void:
	for i in range(count):
		var angle: float = offset + TAU * float(i) / count
		if absf(wrapf(angle - gap, -PI, PI)) > half_gap:
			_add_bullet(position, Vector2.from_angle(angle) * speed, radius, color)

func _spawn_boss() -> void:
	_boss_spawned = true
	for enemy in enemies:
		_add_effect(enemy["pos"], "clear", 34.0, 0.5)
	enemies.clear()
	bullets.clear()
	wave = 12
	stage_label = "WARNING · HARBINGER"
	boss = {"id": _next_id, "type": "boss", "name": "HARBINGER", "pos": Vector2(field_size.x * 0.5, -90.0),
		"hp": 2400.0, "max_hp": 2400.0, "radius": 58.0, "phase": 1, "phase_time": 0.0,
		"age": 0.0, "telegraph": 3.0, "timer": 0.4, "aim_timer": 1.6, "flash": 0.0,
		"pattern_index": 0, "warning_angle": PI * 0.5,
		"rotation": 0.0, "rotation_speed": 0.28, "bank": 0.0, "iris_rotation": 0.0, "hub_rotation": 0.0,
		"blade_openings": PackedFloat32Array([0.04, 0.04, 0.04, 0.04, 0.04, 0.04]), "iris_opening": 0.04, "attack_telegraph": 0.0, "choreography_slot": 0, "cycle_time": 0.0, "pattern_rotation": 0.0, "spiral_tick": 0}
	_next_id += 1
	last_event = "boss_warning"

## Deterministic capture / QA entry point. No random seed or wall clock is used.
func debug_set_boss(phase: int = 1) -> void:
	start()
	elapsed = BOSS_TIME
	power = 4
	_spawn_boss()
	boss["pos"] = Vector2(field_size.x * 0.5, 205.0)
	boss["age"] = 3.0
	boss["telegraph"] = 1.2
	boss["phase"] = clampi(phase, 1, 3)
	if phase == 2:
		boss["hp"] = 1550.0
	elif phase >= 3:
		boss["hp"] = 760.0
	invulnerable = 2.0

func _update_boss(dt: float) -> void:
	if boss.is_empty() or float(boss["hp"]) <= 0.0:
		return
	boss["age"] += dt
	boss["phase_time"] += dt
	# Every visible rotor turns clockwise in screen coordinates (positive radians).
	# Rotation/hinges are simulation-owned, not render time or a reversible sine wave.
	var previous_position: Vector2 = boss["pos"]
	boss["flash"] = maxf(0.0, float(boss["flash"]) - dt)
	var time_before: float = boss["cycle_time"]
	boss["phrase"] = "reposition" if time_before < 1.5 else ("blades" if time_before < 2.6 else ("curves" if time_before < 4.7 else ("spiral" if time_before >= 5.2 and time_before < 9.6 else ("expand" if time_before < 11.0 else "rest"))))
	if float(boss["telegraph"]) > 0.0:
		boss["pos"] = Vector2(boss["pos"]).lerp(Vector2(field_size.x * 0.5, 205.0), 1.0 - exp(-2.4 * dt))
	elif boss.has("move_from") and int(boss["choreography_slot"]) != 0:
		var u := clampf(time_before / 1.35, 0.0, 1.0)
		u = u * u * (3.0 - 2.0 * u)
		boss["pos"] = Vector2(boss["move_from"]).lerp(Vector2(boss["move_to"]), u)
	var ratio: float = float(boss["hp"]) / float(boss["max_hp"])
	var phase: int = 1 if ratio > 0.66667 else (2 if ratio > 0.33334 else 3)
	if phase != int(boss["phase"]):
		boss["phase"] = phase
		boss["phase_time"] = 0.0
		boss["telegraph"] = 1.8
		boss["timer"] = 0.25
		boss["aim_timer"] = 1.3
		boss["pattern_index"] = 0
		boss["choreography_slot"] = 0
		boss["cycle_time"] = 0.0
		boss["spiral_tick"] = 0
		boss["attack_telegraph"] = 0.0
		score += bullets.size() * 3
		bullets.clear()
		_add_effect(boss["pos"], "phase", 190.0, 1.5)
		last_event = "phase_change"
	_update_boss_animation(dt, previous_position)
	if float(boss["telegraph"]) > 0.0:
		boss["telegraph"] = maxf(0.0, float(boss["telegraph"]) - dt)
		stage_label = "WARNING · HARBINGER / PHASE %d" % phase
		return
	stage_label = ["", "HARBINGER · PETAL CASCADE", "HARBINGER · ROTATING HALO", "HARBINGER · LAST BLOOM"][phase]
	var pos: Vector2 = boss["pos"]
	boss["attack_telegraph"] = maxf(0.0, float(boss["attack_telegraph"]) - dt)
	boss["cycle_time"] += dt
	var time: float = boss["cycle_time"]
	var slot: int = boss["choreography_slot"]
	# A single score orders reposition, locked needles, full-angle blooms,
	# rapid spiral, expansion and rest. Internal locks have no visible overlays.
	var beats := [0.0, 1.6, 2.05, 2.6, 3.25, 3.9, 4.55, 14.4]
	if time >= beats[slot]:
		match slot:
			0:
				boss["move_from"] = boss["pos"]
				var cycle: int = boss.get("cycle_index", 0)
				boss["move_to"] = Vector2(field_size.x * (0.36 if cycle % 2 == 0 else 0.64), 205.0 + (cycle % 2) * 25.0)
				boss["cycle_index"] = cycle + 1
				boss["warning_angle"] = (player - pos).angle()
				boss["attack_telegraph"] = 1.6
			1, 2:
				if player.distance_to(pos) >= 150.0:
					_boss_fan(1 if slot == 1 else 4, float(boss["warning_angle"]), 5, 0.13, 290.0, GOLD, 3.5, "needle", 0.0)
			3:
				boss["pattern_rotation"] = boss["rotation"]
				boss["attack_telegraph"] = 0.65
			4, 5, 6:
				# Complete 360-degree blooms. Safety comes from inter-bullet spacing,
				# not a player-centered angular deletion that erases the entire lower fan.
				var count := 24 + phase * 6
				var offset: float = float(boss["pattern_rotation"]) + (slot - 4) * TAU / count * .38
				_boss_radial_ring(count, offset, 175.0 + phase * 8.0, PINK if slot != 5 else GOLD, .055 if slot != 5 else -.055)
				boss["pattern_index"] += 1
			7:
				boss["cycle_time"] = 0.0
				boss["spiral_tick"] = 0
				boss["choreography_slot"] = -1
		boss["choreography_slot"] += 1

	# Six interleaved corkscrew arms from the real moving tips. Integer score ticks
	# avoid render-rate drift. Four .70s emission phrases have .20s breathing space each:
	# the empty annuli travel outwards with the barrage, providing repeatable routes.
	while time < 9.6 and int(boss["spiral_tick"]) < 90 and time + .000001 >= 6.0 + int(boss["spiral_tick"]) * .04:
		var tick: int = boss["spiral_tick"]
		if fmod(tick * .04 + .000001, .9) < .70:
			_boss_spiral_volley(phase, int(tick * .04 / .9))
		boss["spiral_tick"] += 1

	if invulnerable <= 0.0 and pos.distance_squared_to(player) < 55.0 * 55.0:
		_hit_player()

## Quintic pose keys: zero velocity/acceleration at each key, with bounded lag
## between the three opposite blade pairs. These are body poses, never warning UI.
static func _boss_pose_key(time: float, keys: Array) -> float:
	if time <= float(keys[0].x):
		return float(keys[0].y)
	for i in range(1, keys.size()):
		if time <= float(keys[i].x):
			var u := inverse_lerp(float(keys[i-1].x), float(keys[i].x), time)
			u = u * u * u * (u * (u * 6.0 - 15.0) + 10.0)
			return lerpf(float(keys[i-1].y), float(keys[i].y), u)
	return float(keys.back().y)

static func boss_opening_at(time: float) -> float:
	return _boss_pose_key(time, [Vector2(0,.04), Vector2(.65,.04), Vector2(1.12,.04),
		Vector2(1.64,.90), Vector2(2.08,1.0), Vector2(2.60,.28), Vector2(2.88,.24),
		Vector2(3.30,1.0), Vector2(3.66,.76), Vector2(3.98,1.0), Vector2(4.55,.88),
		Vector2(5.05,.12), Vector2(5.45,.12), Vector2(5.95,1.0), Vector2(9.60,1.0),
		Vector2(10.65,.04), Vector2(11.0,.04), Vector2(14.4,.04)])

func _update_boss_animation(dt: float, previous_position: Vector2) -> void:
	var time: float = boss["cycle_time"]
	var entering: bool = float(boss["telegraph"]) > 0.0
	var intensity: float = 1.0 + (int(boss["phase"]) - 1) * .12
	var target_speed := .38 if entering else _boss_pose_key(time, [Vector2(0,.45), Vector2(.65,.45),
		Vector2(.85,.60), Vector2(1.30,2.8), Vector2(1.87,2.25), Vector2(2.12,3.05),
		Vector2(2.60,.70), Vector2(2.86,.70), Vector2(3.23,3.50), Vector2(3.65,2.65),
		Vector2(3.98,3.75), Vector2(4.55,3.5), Vector2(5.0,1.5), Vector2(5.25,1.5),
		Vector2(5.92,6.2), Vector2(9.60,6.2), Vector2(10.65,.38), Vector2(11.0,.28),
		Vector2(13.8,.28), Vector2(14.4,.45)]) * intensity
	var previous_speed: float = boss["rotation_speed"]
	var eased_speed := lerpf(previous_speed, target_speed, 1.0 - exp(-9.0 * dt))
	# A phase clear can interrupt peak spin; decelerate rather than snapping the rotor.
	boss["rotation_speed"] = move_toward(previous_speed, eased_speed, 16.0 * dt)
	boss["rotation"] = wrapf(float(boss["rotation"]) + (previous_speed + float(boss["rotation_speed"])) * .5 * dt, -PI, PI)
	var velocity := (Vector2(boss["pos"]) - previous_position) / maxf(dt, .000001)
	boss["bank"] = lerpf(float(boss["bank"]), clampf(-velocity.x / 1100.0, -.08, .08), 1.0 - exp(-2.0 * dt))
	for blade in 6:
		var target := .04 if entering else boss_opening_at(time - (blade % 3) * .075)
		boss["blade_openings"][blade] = lerpf(float(boss["blade_openings"][blade]), target, 1.0 - exp(-(6.0 if entering else 13.0) * dt))
	# Inner iris follows late, while the hub is geared down, so layers do not read as a rigid decal.
	var iris_target := .04 if entering else boss_opening_at(time - .22)
	boss["iris_opening"] = lerpf(float(boss["iris_opening"]), iris_target, 1.0 - exp(-8.0 * dt))
	boss["iris_rotation"] = wrapf(float(boss["iris_rotation"]) + (.14 + float(boss["rotation_speed"]) * .53) * dt, -PI, PI)
	boss["hub_rotation"] = wrapf(float(boss["hub_rotation"]) + (.10 + float(boss["rotation_speed"]) * .24) * dt, -PI, PI)

## One fixed, cacheable curved scythe profile in hinge-local space.
const BOSS_BLADE_TIP := Vector2(57,-12)
static func boss_blade_polygon() -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(9):
		var t := float(i)/8.0
		points.append(Vector2(-5,-8)*(1-t)*(1-t) + Vector2(18,-34)*2*(1-t)*t + BOSS_BLADE_TIP*t*t)
	for i in range(1,9):
		var t := float(i)/8.0
		points.append(BOSS_BLADE_TIP*(1-t)*(1-t) + Vector2(27,-18)*2*(1-t)*t + Vector2(8,13)*t*t)
	points.append_array(PackedVector2Array([Vector2(1,14),Vector2(6,1)]))
	return points

## The full articulated transform is shared by drawing AND bullet birth positions.
## Opening extends the root and swings its hinge; banking is part of this same transform.
static func blade_transform(index: int, rotation: float, opening: float = .04, bank: float = 0.0) -> Transform2D:
	var axis_angle := index * TAU / 6.0 - PI * .5 + rotation + bank
	var root := Vector2.from_angle(axis_angle) * (54.0 + opening * 23.0)
	var hinge := .76 - opening * .86
	return Transform2D(axis_angle + hinge, root)

static func blade_tip_offset(index: int, rotation: float, opening: float = .04, bank: float = 0.0) -> Vector2:
	return blade_transform(index, rotation, opening, bank) * BOSS_BLADE_TIP

func boss_blade_position(index: int) -> Vector2:
	return Vector2(boss["pos"]) + blade_tip_offset(index, float(boss["rotation"]), float(boss["blade_openings"][index]), float(boss["bank"]))

func _boss_fan(blade: int, angle: float, count: int, spacing: float, speed: float, color: Color, radius: float, kind: String, curve: float) -> void:
	var origin := boss_blade_position(blade)
	if origin.distance_to(player) < 140.0:
		return
	for i in range(count):
		_add_bullet(origin, Vector2.from_angle(angle + (i - (count - 1) * 0.5) * spacing) * speed, radius, color, kind, curve)

## Preserve a complete pattern near the player: suppress the WHOLE volley rather
## than deleting individual nearby/lower tips. No angular fairness filter.
func _boss_volley_clearance() -> bool:
	for blade in 6:
		if boss_blade_position(blade).distance_to(player) < 140.0:
			return false
	return true

func _boss_radial_ring(count: int, offset: float, speed: float, color: Color, curve: float = 0.0) -> void:
	if not _boss_volley_clearance() or bullets.size() + count > MAX_BULLETS:
		return
	for i in count:
		var angle := offset + TAU * float(i) / count
		var blade := 0
		var best := INF
		for candidate in 6:
			var radial := (boss_blade_position(candidate) - Vector2(boss["pos"])).angle()
			var error := absf(wrapf(angle - radial, -PI, PI))
			if error < best:
				best = error
				blade = candidate
		_add_bullet(boss_blade_position(blade), Vector2.from_angle(angle) * speed, 5.5, color, "orb", curve)
		bullets.back()["curve_duration"] = 2.2
		bullets.back()["pattern"] = "radial"

func _boss_spiral_volley(phase: int, pulse: int) -> void:
	if not _boss_volley_clearance() or bullets.size() + 6 > MAX_BULLETS:
		return
	for blade in 6:
		var origin := boss_blade_position(blade)
		var heading := (origin - Vector2(boss["pos"])).normalized()
		_add_bullet(origin, heading * (200.0 + phase * 10.0), 4.5, PINK if blade % 2 == 0 else PURPLE, "orb", .16)
		bullets.back()["curve_duration"] = 3.0
		bullets.back()["pattern"] = "spiral"
		bullets.back()["pulse"] = pulse

func _fire_player() -> void:
	var spread: float = 0.0 if focused else 0.11
	_add_shot(player + Vector2(-8.0, -21.0), Vector2(0.0, -950.0), 5.0)
	_add_shot(player + Vector2(8.0, -21.0), Vector2(0.0, -950.0), 5.0)
	if power >= 2:
		_add_shot(player + Vector2(-22.0, -8.0), Vector2(-spread, -1.0).normalized() * 890.0, 3.5)
		_add_shot(player + Vector2(22.0, -8.0), Vector2(spread, -1.0).normalized() * 890.0, 3.5)
	if power >= 3:
		_add_shot(player + Vector2(-35.0, 4.0), Vector2(-spread * 2.0, -1.0).normalized() * 850.0, 3.5)
		_add_shot(player + Vector2(35.0, 4.0), Vector2(spread * 2.0, -1.0).normalized() * 850.0, 3.5)
	if power >= 4:
		_add_shot(player + Vector2(0.0, -27.0), Vector2(0.0, -1050.0), 5.0)

func _add_shot(position: Vector2, velocity: Vector2, damage: float) -> void:
	if shots.size() < MAX_SHOTS:
		shots.append({"pos": position, "vel": velocity, "damage": damage, "radius": 4.0})

func _update_shots(dt: float) -> void:
	for i in range(shots.size() - 1, -1, -1):
		var shot: Dictionary = shots[i]
		var previous: Vector2 = shot["pos"]
		var pos: Vector2 = previous + Vector2(shot["vel"]) * dt
		shot["pos"] = pos
		var consumed := false
		for j in range(enemies.size() - 1, -1, -1):
			var enemy: Dictionary = enemies[j]
			if _segment_distance_squared(enemy["pos"], previous, pos) < pow(float(enemy["radius"]) + 4.0, 2.0):
				enemy["hp"] -= float(shot["damage"])
				enemy["flash"] = 0.075
				consumed = true
				if float(enemy["hp"]) <= 0.0:
					_destroy_enemy(j)
				break
		if not consumed and not boss.is_empty() and float(boss["hp"]) > 0.0:
			if _segment_distance_squared(boss["pos"], previous, pos) < 62.0 * 62.0:
				# Opening and phase warning windows are invulnerable, not skippable.
				if float(boss["telegraph"]) <= 0.0:
					boss["hp"] = maxf(0.0, float(boss["hp"]) - float(shot["damage"]))
					boss["flash"] = 0.07
					if float(boss["hp"]) <= 0.0:
						_win()
				consumed = true
		if consumed or pos.y < -60.0 or pos.x < -60.0 or pos.x > field_size.x + 60.0:
			shots.remove_at(i)

func _destroy_enemy(index: int, drops: bool = true) -> void:
	var enemy: Dictionary = enemies[index]
	var pos: Vector2 = enemy["pos"]
	kills += 1
	score += 700 if enemy["type"] in ["gunner", "sweeper", "orbiter"] else (400 if enemy["type"] in ["weaver", "sniper"] else 250)
	_add_effect(pos, "explosion", float(enemy["radius"]) * 2.1, 0.52)
	if drops:
		_add_pickup(pos, "power" if kills % 4 == 0 or enemy["type"] in ["gunner", "sniper", "sweeper", "orbiter"] else "score")
		if kills % 17 == 0:
			_add_pickup(pos + Vector2(22.0, 0.0), "bomb")
	enemies.remove_at(index)

func _fan(position: Vector2, angle: float, count: int, spacing: float, speed: float, color: Color, radius: float, kind: String = "orb") -> void:
	for i in range(count):
		var a: float = angle + (i - (count - 1) * 0.5) * spacing
		_add_bullet(position, Vector2.from_angle(a) * speed, radius, color, kind)

func _ring(position: Vector2, count: int, offset: float, speed: float, color: Color, radius: float) -> void:
	for i in range(count):
		_add_bullet(position, Vector2.from_angle(offset + TAU * float(i) / count) * speed, radius, color)

func _add_bullet(position: Vector2, velocity: Vector2, radius: float, color: Color, kind: String = "orb", angular_velocity: float = 0.0) -> void:
	if bullets.size() < MAX_BULLETS:
		bullets.append({"pos": position, "vel": velocity, "radius": radius, "color": color,
			"kind": kind, "grazed": false, "age": 0.0, "angular_velocity": angular_velocity, "curve_duration": 3.0, "origin": position})
		# A finite travelling front, not a lingering screen-sized absorber. New shots
		# fully behind it are allowed; births ahead of it are still swept normally.
		for shield in damage_waves:
			if position.distance_to(shield["pos"]) + radius < float(shield["radius"]):
				if not bullets.back().has("passed_waves"):
					bullets.back()["passed_waves"] = {}
				bullets.back()["passed_waves"][shield["id"]] = true

## Smooth acceleration is reserved for rare, distant straight needles.
func _add_accelerating_bullet(position: Vector2, direction: Vector2, start_speed: float, end_speed: float) -> void:
	if bullets.size() >= MAX_BULLETS:
		return
	_add_bullet(position, direction.normalized() * start_speed, 3.5, GOLD, "needle")
	var b: Dictionary = bullets.back()
	b["speed_start"] = start_speed
	b["speed_end"] = end_speed
	b["accel_delay"] = 0.8
	b["accel_duration"] = 1.2

static func bullet_travel_at(b: Dictionary, age: float) -> float:
	var start_speed: float = b.get("speed_start", Vector2(b["vel"]).length())
	var end_speed: float = b.get("speed_end", start_speed)
	var delay: float = b.get("accel_delay", 0.0)
	var duration: float = maxf(0.001, b.get("accel_duration", 1.0))
	var u := clampf((age - delay) / duration, 0.0, 1.0)
	# Integral of smoothstep: u^3 - .5u^4; derivative joins continuously.
	return start_speed * age + (end_speed - start_speed) * (duration * (u*u*u - 0.5*u*u*u*u) + maxf(0.0, age-delay-duration))

func _update_bullets(dt: float) -> void:
	var wave_id_before := _next_damage_wave_id
	for i in range(bullets.size() - 1, -1, -1):
		var bullet: Dictionary = bullets[i]
		var previous: Vector2 = bullet["pos"]
		var velocity: Vector2 = bullet["vel"]
		var curve: float = bullet.get("angular_velocity", 0.0)
		var pos: Vector2
		var curve_dt: float = minf(dt, maxf(0.0, float(bullet.get("curve_duration", 3.0)) - float(bullet.get("age", 0.0))))
		if bullet.has("speed_end"):
			var age: float = bullet["age"]
			var travel := bullet_travel_at(bullet, age + dt) - bullet_travel_at(bullet, age)
			pos = previous + velocity.normalized() * travel
			var u := clampf((age + dt - float(bullet["accel_delay"])) / float(bullet["accel_duration"]), 0.0, 1.0)
			bullet["vel"] = velocity.normalized() * lerpf(bullet["speed_start"], bullet["speed_end"], u*u*(3.0-2.0*u))
		elif absf(curve) > 0.00001 and curve_dt > 0.0:
			# Exact arc then tangent flight. Capping the bend at three seconds keeps
			# tall portrait travel from closing the deliberately open escape wedge.
			var turned := velocity.rotated(curve * curve_dt)
			pos = previous + Vector2(turned.y - velocity.y, velocity.x - turned.x) / curve + turned * (dt - curve_dt)
			bullet["vel"] = turned
		else:
			pos = previous + velocity * dt
		bullet["pos"] = pos
		bullet["age"] = float(bullet.get("age", 0.0)) + dt
		if not damage_waves.is_empty():
			var contact := _damage_wave_contact(bullet, previous, pos)
			if not contact.is_empty():
				_cancel_bullet(bullet, previous.lerp(pos, contact["time"]), contact["origin"], dt * (1.0-contact["time"]))
				bullets.remove_at(i)
				continue
		var distance: float = _segment_distance_squared(player, previous, pos)
		var radius: float = bullet["radius"]
		if invulnerable <= 0.0 and distance < pow(radius + PLAYER_RADIUS, 2.0):
			var hit_origin := player
			_hit_player()
			# The striking bullet is harmless immediately, not one visual frame later.
			_cancel_bullet(bullet, hit_origin, hit_origin, 0.0)
			bullets.remove_at(i)
			if state != "playing": return
			continue
		if not bool(bullet.get("grazed", false)) and invulnerable <= 0.0 and distance < pow(radius + 25.0, 2.0):
			bullet["grazed"] = true
			graze += 1
			score += 20
		if pos.x < -70.0 or pos.x > field_size.x + 70.0 or pos.y < -150.0 or pos.y > field_size.y + 70.0 or float(bullet["age"]) > clampf(field_size.y / maxf(75.0, velocity.length()) + 4.0, 16.0, 28.0):
			bullets.remove_at(i)
			continue

	# A hit can be detected halfway through this reverse loop. Sweep its initial
	# contact area once more so already-updated bullets do not remain visibly live.
	if _next_damage_wave_id != wave_id_before:
		for i in range(bullets.size()-1,-1,-1):
			var bullet: Dictionary = bullets[i]
			for shield in damage_waves:
				if shield["id"] < wave_id_before: continue
				if Vector2(bullet["pos"]).distance_to(shield["pos"]) <= float(shield["radius"])+float(bullet["radius"]):
					_cancel_bullet(bullet,bullet["pos"],shield["pos"],0.0)
					bullets.remove_at(i)
					break

## Shared by simulation and drawing. Ease in/out joins smoothly; every swept test
## uses the same two sampled radii as the visible front (120 Hz physics maximum).
static func damage_wave_radius(shield: Dictionary) -> float:
	var t := clampf(float(shield["age"]) / DAMAGE_WAVE_DURATION, 0.0, 1.0)
	return lerpf(14.0, shield["max_radius"], t*t*(3.0-2.0*t))

func _damage_wave_extent(origin: Vector2) -> float:
	var extent := 0.0
	# Include the retained offscreen projectile margin, not just visible corners.
	for corner in [Vector2(-70,-150), Vector2(field_size.x+70,-150), Vector2(-70,field_size.y+70), field_size+Vector2(70,70)]:
		extent = maxf(extent, origin.distance_to(corner))
	return extent + 16.0

func _start_damage_wave(origin: Vector2) -> void:
	if damage_waves.size() >= MAX_DAMAGE_WAVES:
		damage_waves.pop_front()
	damage_waves.append({"id": _next_damage_wave_id, "pos": origin, "age": 0.0,
		"max_radius": _damage_wave_extent(origin), "radius": 14.0, "previous_radius": 14.0})
	_next_damage_wave_id += 1

func _update_damage_waves(dt: float) -> void:
	for i in range(damage_waves.size()-1,-1,-1):
		var shield: Dictionary = damage_waves[i]
		# Keep the last interval alive until all bullets have tested its final sweep.
		if float(shield["age"]) >= DAMAGE_WAVE_DURATION:
			damage_waves.remove_at(i)
			continue
		shield["previous_radius"] = shield["radius"]
		shield["age"] = minf(DAMAGE_WAVE_DURATION, float(shield["age"])+dt)
		shield["radius"] = damage_wave_radius(shield)

## Earliest segment / expanding-disc intersection, including an outside->outside
## tunnel through the wave. Solve |p + v*t|² = (r + dr*t)², t in [0,1].
## Radii include the hostile collision core, not its decorative wake or glow.
static func swept_wave_time(from: Vector2, to: Vector2, origin: Vector2, r0: float, r1: float, bullet_radius: float) -> float:
	var p := from-origin
	var v := to-from
	var r := r0+bullet_radius
	var dr := r1-r0
	var a := v.length_squared()-dr*dr
	var b := 2.0*(p.dot(v)-r*dr)
	var c := p.length_squared()-r*r
	if c <= 0.0: return 0.0
	if absf(a) < 0.000001:
		if b >= -0.000001: return -1.0
		var linear := -c/b
		return linear if linear >= 0.0 and linear <= 1.0 else -1.0
	var discriminant := b*b-4.0*a*c
	if discriminant < 0.0: return -1.0
	var root := sqrt(maxf(0.0,discriminant))
	# Stable quadratic roots avoid losing the near-origin solution to cancellation.
	var q := -0.5*(b+root*(1.0 if b >= 0.0 else -1.0))
	var first := q/a
	var second := c/q if absf(q) > 0.000001 else -1.0
	var result := INF
	if first >= 0.0 and first <= 1.0: result = first
	if second >= 0.0 and second <= 1.0: result = minf(result,second)
	return result if is_finite(result) else -1.0

func _damage_wave_contact(bullet: Dictionary, from: Vector2, to: Vector2) -> Dictionary:
	var earliest := 2.0
	var origin := Vector2.ZERO
	for shield in damage_waves:
		if bullet.get("passed_waves", {}).has(shield["id"]): continue
		var time := swept_wave_time(from,to,shield["pos"],shield["previous_radius"],shield["radius"],bullet["radius"])
		if time >= 0.0 and time < earliest:
			earliest = time
			origin = shield["pos"]
	return {"time": earliest, "origin": origin} if earliest <= 1.0 else {}

func _cancel_bullet(bullet: Dictionary, position: Vector2, origin: Vector2, initial_age: float) -> void:
	var remnant: Dictionary
	if cancel_effects.size() >= MAX_CANCEL_EFFECTS:
		remnant = cancel_effects.pop_front()
	elif not _cancel_pool.is_empty():
		remnant = _cancel_pool.pop_back()
	else:
		remnant = {}
	remnant["pos"] = position
	remnant["radius"] = bullet.get("radius",6.0)
	remnant["color"] = bullet.get("color",PINK)
	remnant["angle"] = (position-origin).angle()
	remnant["age"] = initial_age
	cancel_effects.append(remnant)

func _update_cancel_effects(dt: float) -> void:
	for i in range(cancel_effects.size()-1,-1,-1):
		cancel_effects[i]["age"] += dt
		if float(cancel_effects[i]["age"]) >= CANCEL_EFFECT_DURATION:
			_cancel_pool.append(cancel_effects[i])
			cancel_effects.remove_at(i)

func _hit_player() -> void:
	if invulnerable > 0.0 or state != "playing":
		return
	lives -= 1
	power = maxi(1, power - 1)
	_start_damage_wave(player)
	_add_effect(player, "hurt", 24.0, 0.32)
	shake = 9.0
	invulnerable = 3.0
	last_event = "player_hit"
	if lives <= 0:
		lives = 0
		state = "lost"
		stage_label = "MISSION FAILED"
	else:
		player = Vector2(field_size.x * 0.5, field_size.y - 150.0)

func _use_bomb() -> void:
	if bombs <= 0 or state != "playing":
		return
	bombs -= 1
	score += bullets.size() * 5
	bullets.clear()
	bomb_flash = 0.8
	shake = 7.0
	invulnerable = maxf(invulnerable, 2.2)
	_add_effect(player, "bomb", 660.0, 0.85)
	for i in range(enemies.size() - 1, -1, -1):
		enemies[i]["hp"] -= 100.0
		if float(enemies[i]["hp"]) <= 0.0:
			_destroy_enemy(i)
	if not boss.is_empty() and float(boss["telegraph"]) <= 0.0:
		boss["hp"] = maxf(0.0, float(boss["hp"]) - 220.0)
		boss["flash"] = 0.3
		if float(boss["hp"]) <= 0.0:
			_win()
	if state == "playing":
		last_event = "bomb"

func _add_pickup(position: Vector2, kind: String) -> void:
	if pickups.size() < MAX_PICKUPS:
		pickups.append({"pos": position, "type": kind, "age": 0.0})

func _update_pickups(dt: float) -> void:
	for i in range(pickups.size() - 1, -1, -1):
		var pickup: Dictionary = pickups[i]
		pickup["age"] += dt
		var pos: Vector2 = pickup["pos"]
		var distance: float = pos.distance_to(player)
		if player.y < field_size.y * 0.25 or distance < 100.0:
			pos = pos.move_toward(player, 400.0 * dt)
		else:
			pos.y += 82.0 * dt
		pickup["pos"] = pos
		if pos.distance_squared_to(player) < 25.0 * 25.0:
			match String(pickup["type"]):
				"power":
					power = mini(4, power + 1)
					score += 300
				"bomb":
					bombs = mini(5, bombs + 1)
					score += 500
				_:
					score += 150
			_add_effect(pos, "pickup", 35.0, 0.35)
			pickups.remove_at(i)
		elif pos.y > field_size.y + 35.0 or float(pickup["age"]) > 20.0:
			pickups.remove_at(i)

func _add_effect(position: Vector2, kind: String, radius: float, life: float) -> void:
	if effects.size() >= MAX_EFFECTS:
		effects.pop_front()
	effects.append({"pos": position, "type": kind, "radius": radius, "age": 0.0, "life": life})

func _update_effects(dt: float) -> void:
	for i in range(effects.size() - 1, -1, -1):
		effects[i]["age"] += dt
		if float(effects[i]["age"]) >= float(effects[i]["life"]):
			effects.remove_at(i)

func _win() -> void:
	if state != "playing":
		return
	state = "won"
	stage_label = "SECTOR CLEAR"
	score += 15000 + lives * 2000 + bombs * 500
	bullets.clear()
	enemies.clear()
	_add_effect(boss["pos"], "victory", 360.0, 2.5)
	shake = 10.0
	last_event = "victory"

static func _segment_distance_squared(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var length_squared: float = ab.length_squared()
	if length_squared < 0.000001:
		return point.distance_squared_to(a)
	var weight: float = clampf((point - a).dot(ab) / length_squared, 0.0, 1.0)
	return point.distance_squared_to(a + ab * weight)
