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
	for collection in [enemies, bullets, shots, pickups, effects]:
		for entity in collection:
			entity["pos"] = Vector2(entity["pos"]) * ratio
			if entity.has("origin_x"):
				entity["origin_x"] = float(entity["origin_x"]) * ratio.x
	if not boss.is_empty():
		boss["pos"] = Vector2(boss["pos"]) * ratio
	field_size = size
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
	enemies.append({"id": _next_id, "type": kind, "pos": position, "origin_x": position.x,
		"hp": health, "max_hp": health, "radius": radius, "speed": speed,
		"age": 0.0, "timer": 0.65 + order * 0.55, "order": order, "flash": 0.0,
		"telegraph": 0.0, "warning_angle": PI * 0.5, "attack_index": 0, "burst_left": 0})
	_next_id += 1

func _update_enemies(dt: float) -> void:
	for i in range(enemies.size() - 1, -1, -1):
		var enemy: Dictionary = enemies[i]
		enemy["age"] += dt
		enemy["flash"] = maxf(0.0, float(enemy["flash"]) - dt)
		var pos: Vector2 = enemy["pos"]
		pos.y += float(enemy["speed"]) * dt
		var age: float = enemy["age"]
		var order: int = enemy["order"]
		if enemy["type"] == "weaver":
			pos.x = clampf(float(enemy["origin_x"]) + sin(age * 1.6 + order * 0.8) * 100.0, 40.0, field_size.x - 40.0)
		elif enemy["type"] == "scout":
			pos.x = clampf(float(enemy["origin_x"]) + sin(age * 1.5 + order) * 40.0, 32.0, field_size.x - 32.0)
		elif enemy["type"] in ["sniper", "sweeper", "orbiter"]:
			# Arrive from above, hold a readable upper-field station, retreat above.
			var station_y: float = 210.0 + order * 30.0
			if age > 7.0:
				pos.y -= (float(enemy["speed"]) + 210.0) * dt
			else:
				pos.y = minf(pos.y, station_y)
			if enemy["type"] == "sweeper":
				pos.x = clampf(float(enemy["origin_x"]) + sin(age * 0.8) * field_size.x * 0.19, 110.0, field_size.x - 110.0)
			elif enemy["type"] == "orbiter":
				pos.x = clampf(float(enemy["origin_x"]) + sin(age * 1.2) * 95.0, 110.0, field_size.x - 110.0)
				if age > 2.5 and age < 7.0:
					pos.y = move_toward(pos.y - float(enemy["speed"]) * dt, station_y + sin(age * 1.2) * 32.0, float(enemy["speed"]) * dt)
		enemy["pos"] = pos
		if age > 9.0 and enemy["type"] in ["sniper", "sweeper", "orbiter"]:
				enemies.remove_at(i)
				continue
		if pos.y > field_size.y + 80.0:
			enemies.remove_at(i)
			continue
		if pos.y > 25.0 and pos.y < field_size.y - 210.0:
			if float(enemy["telegraph"]) > 0.0:
				enemy["telegraph"] = maxf(0.0, float(enemy["telegraph"]) - dt)
				if float(enemy["telegraph"]) <= 0.0:
					_enemy_fire(enemy)
			else:
				enemy["timer"] -= dt
				if float(enemy["timer"]) <= 0.0 and age < 7.0:
					# Lock once, before the flash. Never track during the warning or burst.
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

func _enemy_fire(enemy: Dictionary) -> void:
	var pos: Vector2 = enemy["pos"]
	# Suppress point-blank emissions and all shots after retreat begins.
	if pos.distance_to(player) < 140.0 or float(enemy["age"]) >= 7.0:
		enemy["timer"] = 0.8
		enemy["burst_left"] = 0
		return
	var aim: float = enemy["warning_angle"]
	match String(enemy["type"]):
		"scout":
			_fan(pos, aim, 3, 0.18, 180.0, PINK, 5.0)
			enemy["timer"] = 1.8
		"gunner":
			_fan(pos, aim, 5, 0.20, 160.0, GOLD, 6.5)
			enemy["timer"] = 2.2
		"weaver":
			_fan(pos, aim, 5, 0.23, 150.0, PURPLE, 5.5)
			enemy["timer"] = 1.65
		"sniper":
			_fan(pos, aim, 3, 0.12, 225.0, GOLD, 4.5, "needle")
			_continue_burst(enemy, 2, 0.25, 2.3)
		"sweeper":
			# Two wings sweep together; the middle lane remains intentionally open.
			var sweep: float = aim + (int(enemy["attack_index"]) % 3 - 1) * 0.12
			_fan(pos, sweep - 0.48, 3, 0.13, 155.0, PINK, 5.5)
			_fan(pos, sweep + 0.48, 3, 0.13, 155.0, PINK, 5.5)
			_continue_burst(enemy, 3, 0.34, 2.1)
		"orbiter":
			_gap_ring(pos, 18, float(enemy["age"]) * 0.2, aim, 0.48, 130.0, PURPLE, 5.5)
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
		"pattern_index": 0, "warning_angle": PI * 0.5, "gap_angle": PI * 0.5,
		"rotation": 0.0, "rotation_speed": 0.16, "attack_telegraph": 0.0, "choreography_slot": 0, "cycle_time": 0.0, "pattern_rotation": 0.0}
	_next_id += 1
	last_event = "boss_warning"

## Deterministic capture / QA entry point. No random seed or wall clock is used.
func debug_set_boss(phase: int = 1) -> void:
	start()
	elapsed = BOSS_TIME
	power = 4
	_spawn_boss()
	boss["pos"] = Vector2(field_size.x * 0.5, 160.0)
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
	# Simulation-owned radians: rendering, pause and refresh rate cannot advance it.
	var slot_now: int = boss["choreography_slot"]
	var attacking: bool = float(boss["telegraph"]) <= 0.0 and slot_now in [2, 3, 5, 6, 7] and float(boss["cycle_time"]) < 4.5
	var target_speed: float = ([0.0, 0.8, -1.05, 1.3][int(boss["phase"])] if attacking else [0.0, 0.16, -0.20, 0.24][int(boss["phase"])])
	var previous_speed: float = boss["rotation_speed"]
	boss["rotation_speed"] = lerpf(previous_speed, target_speed, 1.0 - exp(-3.0 * dt))
	boss["rotation"] = wrapf(float(boss["rotation"]) + (previous_speed + float(boss["rotation_speed"])) * 0.5 * dt, -PI, PI)
	boss["flash"] = maxf(0.0, float(boss["flash"]) - dt)
	var age: float = boss["age"]
	var target := Vector2(field_size.x * 0.5 + sin(age * 0.42) * field_size.x * 0.2, 148.0 + sin(age * 0.83) * 24.0)
	var position: Vector2 = boss["pos"]
	boss["pos"] = position.move_toward(target, 160.0 * dt)
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
		boss["attack_telegraph"] = 0.0
		score += bullets.size() * 3
		bullets.clear()
		_add_effect(boss["pos"], "phase", 190.0, 1.5)
		last_event = "phase_change"
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
	# A single score orders every emission: aim cue, locked double burst,
	# gap cue, rotating blade rings, then a long breathing window.
	var beats := [0.0, 0.55, 0.95, 2.0, 2.75, 3.45, 4.15, 7.2]
	if time >= beats[slot]:
		match slot:
			0:
				boss["warning_angle"] = (player - pos).angle()
				boss["attack_telegraph"] = 0.55
			1, 2:
				if player.distance_to(pos) >= 150.0:
					_boss_fan(slot - 1, float(boss["warning_angle"]), 5 if phase == 3 else 3, 0.15, 205.0, GOLD, 4.5, "needle", 0.12 if phase != 2 else -0.12)
			3:
				boss["gap_angle"] = clampf((player - pos).angle(), 0.45, PI - 0.45)
				boss["pattern_rotation"] = boss["rotation"]
				boss["attack_telegraph"] = 0.75
			4, 5, 6:
				if slot < 6 or phase == 3:
					var offset: float = float(boss["pattern_rotation"]) + (slot - 4) * (0.12 if phase != 2 else -0.16)
					_boss_gap_ring(18 + phase * 4, offset, float(boss["gap_angle"]), 0.64 if phase == 3 else 0.70, 135.0 + phase * 5.0, PINK if phase == 1 else PURPLE, 0.11 if phase != 2 else -0.11)
					boss["pattern_index"] += 1
			7:
				boss["cycle_time"] = 0.0
				boss["choreography_slot"] = -1
		boss["choreography_slot"] += 1

	if invulnerable <= 0.0 and pos.distance_squared_to(player) < 55.0 * 55.0:
		_hit_player()

## Shared by the renderer and emitters: the six colored blade tips, never the core.
static func blade_tip_offset(index: int, rotation: float) -> Vector2:
	var axis := Vector2.from_angle(index * TAU / 6.0 - PI * 0.5 + rotation)
	return axis * 58.0 * 1.67 + axis.orthogonal() * 22.0

func boss_blade_position(index: int) -> Vector2:
	return Vector2(boss["pos"]) + blade_tip_offset(index, float(boss["rotation"]))

func _boss_fan(blade: int, angle: float, count: int, spacing: float, speed: float, color: Color, radius: float, kind: String, curve: float) -> void:
	var origin := boss_blade_position(blade)
	if origin.distance_to(player) < 140.0:
		return
	for i in range(count):
		_add_bullet(origin, Vector2.from_angle(angle + (i - (count - 1) * 0.5) * spacing) * speed, radius, color, kind, curve)

func _boss_gap_ring(count: int, offset: float, gap: float, half_gap: float, speed: float, color: Color, curve: float) -> void:
	for i in range(count):
		var angle: float = offset + TAU * float(i) / count
		if absf(wrapf(angle - gap, -PI, PI)) > half_gap:
			var blade: int = posmod(int(round((angle - float(boss["rotation"]) + PI * 0.5) / (TAU / 6.0))), 6)
			var origin := boss_blade_position(blade)
			if origin.distance_to(player) >= 140.0:
				_add_bullet(origin, Vector2.from_angle(angle) * speed, 5.5, color, "orb", curve)

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

func _update_bullets(dt: float) -> void:
	for i in range(bullets.size() - 1, -1, -1):
		var bullet: Dictionary = bullets[i]
		var previous: Vector2 = bullet["pos"]
		var velocity: Vector2 = bullet["vel"]
		var curve: float = bullet.get("angular_velocity", 0.0)
		var pos: Vector2
		var curve_dt: float = minf(dt, maxf(0.0, float(bullet.get("curve_duration", 3.0)) - float(bullet.get("age", 0.0))))
		if absf(curve) > 0.00001 and curve_dt > 0.0:
			# Exact arc then tangent flight. Capping the bend at three seconds keeps
			# tall portrait travel from closing the deliberately open escape wedge.
			var turned := velocity.rotated(curve * curve_dt)
			pos = previous + Vector2(turned.y - velocity.y, velocity.x - turned.x) / curve + turned * (dt - curve_dt)
			bullet["vel"] = turned
		else:
			pos = previous + velocity * dt
		bullet["pos"] = pos
		bullet["age"] = float(bullet.get("age", 0.0)) + dt
		var distance: float = _segment_distance_squared(player, previous, pos)
		var radius: float = bullet["radius"]
		if invulnerable <= 0.0 and distance < pow(radius + PLAYER_RADIUS, 2.0):
			_hit_player()
			# _hit_player clears all bullets, so do not keep iterating this array.
			return
		if not bool(bullet.get("grazed", false)) and invulnerable <= 0.0 and distance < pow(radius + 25.0, 2.0):
			bullet["grazed"] = true
			graze += 1
			score += 20
		if pos.x < -70.0 or pos.x > field_size.x + 70.0 or pos.y < -150.0 or pos.y > field_size.y + 70.0 or float(bullet["age"]) > 16.0:
			bullets.remove_at(i)
			continue

func _hit_player() -> void:
	if invulnerable > 0.0 or state != "playing":
		return
	lives -= 1
	power = maxi(1, power - 1)
	_add_effect(player, "death", 145.0, 1.0)
	shake = 9.0
	bullets.clear()
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
