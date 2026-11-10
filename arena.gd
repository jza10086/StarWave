extends "res://games/minigame/gp_star_wave/game_core.gd"
## Host simulation: one arena contains all pilots, enemies, pickups and projectiles.
## Original enemy routes/boss choreography remain in game_core; ownership is explicit here.
var pilots: Dictionary = {}
var owner: String = ""
var team_mode: bool = false
var survival: float = 0.0
var cleared: bool = false
var cleared_stages: int = 0
var transition_time: float = 0.0
var feedback_sequence: int = 0
# Display positions reconcile to received pilot targets.
var pilot_draw_positions: Dictionary = {}

func configure(roster: Array, team: bool) -> void:
	start()
	team_mode = team
	pilots.clear()
	pilot_draw_positions.clear()
	for index: int in roster.size():
		var entry: Dictionary = roster[index]
		pilots[entry.id] = {"name": entry.name, "color": entry.color, "pos": Vector2(FIELD.x * (index + 1) / (roster.size() + 1), FIELD.y - 150), "lives": 3, "bombs": 3, "power": 1, "invulnerable": 1.8, "timer": 0.0, "score": 0, "kills": 0, "hurt": 0, "boss_damage": 0.0, "move": Vector2.ZERO, "fire": false, "focus": false, "bomb": false, "latch": false, "last_input": 0.0}
		pilot_draw_positions[entry.id] = pilots[entry.id].pos

## Advance local presentation from spawn parameters; this never runs collisions or spawning.
## No spawning, collision, damage, rewards or gameplay timers run on this path.
func advance_presentation(dt: float) -> void:
	if state != "playing":
		return
	for enemy: Dictionary in enemies:
		enemy.age += dt
		enemy.flash = maxf(0.0, float(enemy.flash) - dt)
		enemy.telegraph = maxf(0.0, float(enemy.telegraph) - dt)
		enemy.pos = enemy_route_position(enemy, enemy.age)
		enemy.velocity = (enemy_route_position(enemy, enemy.age + 0.002) - enemy_route_position(enemy, maxf(0.0, enemy.age - 0.002))) / 0.004
		var bank: float = clampf(-Vector2(enemy.velocity).x / 520.0, -0.30, 0.30)
		enemy.rotation = lerpf(float(enemy.rotation), bank, 1.0 - exp(-dt * 7.0))
	if not boss.is_empty() and float(boss.hp) > 0.0:
		var previous_position: Vector2 = boss.pos
		boss.age += dt
		boss.flash = maxf(0.0, float(boss.flash) - dt)
		boss.attack_telegraph = maxf(0.0, float(boss.attack_telegraph) - dt)
		if float(boss.telegraph) > 0.0:
			boss.pos = Vector2(boss.pos).lerp(Vector2(field_size.x * 0.5, 205.0), 1.0 - exp(-2.4 * dt))
		elif boss.has("move_from") and int(boss.choreography_slot) != 0:
			var progress: float = clampf(float(boss.cycle_time) / 1.35, 0.0, 1.0)
			progress = progress * progress * (3.0 - 2.0 * progress)
			boss.pos = Vector2(boss.move_from).lerp(Vector2(boss.move_to), progress)
		_update_boss_animation(dt, previous_position)
		if float(boss.telegraph) > 0.0:
			boss.telegraph = maxf(0.0, float(boss.telegraph) - dt)
		else:
			boss.cycle_time += dt
	for pickup: Dictionary in pickups:
		pickup.age += dt
		pickup.pos.y += 82.0 * dt
	_update_effects(dt)
	_update_damage_waves(dt)
	_update_cancel_effects(dt)

## New pilot targets preserve an existing displayed position.
func receive_pilots(snapshot_pilots: Dictionary) -> void:
	pilots = snapshot_pilots
	for id: String in pilots:
		if not pilot_draw_positions.has(id):
			pilot_draw_positions[id] = pilots[id].pos

## Follow current local input immediately; bound reconciliation below even focus speed.
## The caller applies the same 150 ms prediction horizon as the rest of the arena.
func advance_pilots(dt: float, local_id: String, movement: Vector2, focus: bool) -> void:
	if state != "playing":
		return
	for id: String in pilots:
		var pilot: Dictionary = pilots[id]
		if pilot.lives <= 0:
			continue
		pilot.invulnerable = maxf(0.0, float(pilot.invulnerable) - dt)
		var direction: Vector2 = movement if id == local_id else Vector2(pilot.move)
		var slow: bool = focus if id == local_id else bool(pilot.focus)
		var displacement: Vector2 = direction * (FOCUS_SPEED if slow else PLAYER_SPEED) * dt
		pilot.pos = (Vector2(pilot.pos) + displacement).clamp(Vector2(24, 90), FIELD - Vector2(24, 34))
		var displayed: Vector2 = (Vector2(pilot_draw_positions[id]) + displacement).clamp(Vector2(24, 90), FIELD - Vector2(24, 34))
		pilot_draw_positions[id] = displayed.move_toward(pilot.pos, 80.0 * dt)

func set_input(id: String, data: Dictionary) -> void:
	if not pilots.has(id) or pilots[id].lives <= 0:
		return
	if not data.get("move") is Vector2 or not data.move.is_finite() or not data.get("fire") is bool or not data.get("focus") is bool or not data.get("bomb") is bool:
		return
	for key: String in ["move", "fire", "focus", "bomb"]:
		pilots[id][key] = data[key]
	pilots[id].move = pilots[id].move.limit_length(1.0)
	pilots[id].last_input = survival

func advance(dt: float) -> void:
	if state != "playing":
		return
	survival += dt
	# Every call is a fixed 1/120 tick from the host. Never let render frame rate alter speed.
	elapsed += dt
	var alive: Array[String] = []
	for id: String in pilots:
		var pilot: Dictionary = pilots[id]
		if pilot.lives <= 0:
			continue
		alive.append(id)
		pilot.invulnerable = maxf(0, pilot.invulnerable - dt)
		if survival - float(pilot.last_input) > 0.4:
			pilot.move = Vector2.ZERO
			pilot.fire = false
			pilot.bomb = false
		pilot.pos += Vector2(pilot.move) * (FOCUS_SPEED if pilot.focus else PLAYER_SPEED) * dt
		pilot.pos = Vector2(pilot.pos).clamp(Vector2(24, 90), FIELD - Vector2(24, 34))
		pilot.timer = maxf(0, pilot.timer - dt)
		owner = id
		player = pilot.pos
		power = pilot.power
		focused = pilot.focus
		if not cleared and pilot.fire and pilot.timer <= 0:
			_fire_player()
			pilot.timer = 0.095
		if not cleared and pilot.bomb and not pilot.latch and pilot.bombs > 0:
			_bomb(id)
		pilot.latch = pilot.bomb
	if alive.is_empty():
		state = "lost"
		return
	if cleared:
		shots.clear()
		transition_time -= dt
		_update_effects(dt)
		_update_shared_pickups(dt)
		if transition_time <= 0.0:
			_begin_next_stage()
		return
	# Target alternates deterministically; invulnerability disables original single-pilot contacts.
	player = pilots[alive[int(survival / 2.0) % alive.size()]].pos
	invulnerable = 999.0
	_update_stage()
	_update_enemies(dt)
	_update_boss(dt)
	_update_shots(dt)
	_update_cancel_effects(dt)
	_update_damage_waves(dt)
	# Original curved trajectories and shield sweeping; host then resolves all pilot contacts.
	for bullet: Dictionary in bullets:
		bullet["previous"] = bullet.pos
	_update_bullets(dt)
	var collidable: Array[String] = []
	var pilot_bounds: Rect2
	for id: String in alive:
		if pilots[id].invulnerable <= 0.0:
			if collidable.is_empty():
				pilot_bounds = Rect2(pilots[id].pos, Vector2.ZERO)
			else:
				pilot_bounds = pilot_bounds.expand(pilots[id].pos)
			collidable.append(id)
	if not collidable.is_empty():
		for index: int in range(bullets.size() - 1, -1, -1):
			var bullet: Dictionary = bullets[index]
			var current: Vector2 = bullet.pos
			var previous: Vector2 = bullet.previous
			var radius: float = float(bullet.radius) + PLAYER_RADIUS
			var bounds: Rect2 = Rect2(previous, Vector2.ZERO).expand(current).grow(radius)
			if not bounds.intersects(pilot_bounds, true):
				continue
			for id: String in collidable:
				var pilot: Dictionary = pilots[id]
				if pilot.lives <= 0 or pilot.invulnerable > 0 or not bounds.has_point(pilot.pos):
					continue
				if _segment_distance_squared(pilot.pos, previous, current) < radius * radius:
					hurt(id)
					bullets.remove_at(index)
					break
	for id: String in alive:
		var pilot: Dictionary = pilots[id]
		if pilot.lives <= 0 or pilot.invulnerable > 0:
			continue
		for enemy: Dictionary in enemies:
			if Vector2(enemy.pos).distance_to(pilot.pos) < float(enemy.radius) * 0.7 + PLAYER_RADIUS:
				hurt(id)
				break
		if not boss.is_empty() and Vector2(boss.pos).distance_to(pilot.pos) < 55:
			hurt(id)
	_update_shared_pickups(dt)
	_update_effects(dt)
	if cleared:
		shots.clear()

## Keep player progression and IDs across stages, but no hostile state crosses the boundary.
func _begin_next_stage() -> void:
	stage_index += 1
	elapsed = 0.0
	wave = 0
	_next_wave_time = 1.8
	_boss_spawned = false
	boss = {}
	cleared = false
	transition_time = 0.0
	shots.clear()
	damage_waves.clear()
	for pilot: Dictionary in pilots.values():
		if pilot.lives > 0:
			pilot.lives = mini(3, pilot.lives + 1)
			pilot.bombs = mini(5, pilot.bombs + 1)
			pilot.invulnerable = 2.0
	_add_effect(FIELD * 0.5, "stage", 180, 1.0)

func _spawn_enemy(kind: String, position_value: Vector2, order: int) -> void:
	if enemies.size() >= MAX_ENEMIES:
		return
	super._spawn_enemy(kind, position_value, order)
	enemies.back().hp *= maxf(1.0, pilots.size() * 0.7)
	enemies.back().max_hp = enemies.back().hp

func _spawn_boss() -> void:
	super._spawn_boss()
	boss.hp *= maxf(1.0, pilots.size() * 0.7)
	boss.max_hp = boss.hp

func _add_shot(position_value: Vector2, velocity: Vector2, damage: float) -> void:
	if shots.size() < MAX_SHOTS * maxi(1, pilots.size()):
		shots.append({"pos": position_value, "vel": velocity, "damage": damage, "radius": 4.0, "owner": owner})

## Snapshot-retained events have stable IDs; presentation consumes each only once.
func _add_effect(position_value: Vector2, kind: String, radius: float, life: float) -> void:
	super._add_effect(position_value, kind, radius, life)
	feedback_sequence += 1
	effects.back()["feedback_id"] = feedback_sequence

func _hit_feedback(target: Dictionary, damage: float, direction: Vector2) -> void:
	_add_effect(target.pos, "hit", 18.0, 0.45)
	var effect: Dictionary = effects.back()
	effect["target_id"] = target.id
	effect["damage"] = minf(damage, float(target.hp))
	effect["direction"] = direction.normalized()
	effect["boss_hit"] = target.type == "boss"

func _destroy_enemy(index: int, drops: bool = true) -> void:
	if pilots.has(owner):
		pilots[owner].kills += 1
		pilots[owner].score += 100
	super._destroy_enemy(index, drops)

func credit_boss(id: String, damage: float) -> void:
	if pilots.has(id):
		pilots[id].boss_damage += damage
		pilots[id].score = pilots[id].kills * 100 - pilots[id].hurt * 200 + floori(pilots[id].boss_damage)

func hurt(id: String) -> void:
	var pilot: Dictionary = pilots[id]
	if pilot.lives <= 0 or pilot.invulnerable > 0:
		return
	pilot.lives -= 1
	pilot.hurt += 1
	pilot.score -= 200
	pilot.power = maxi(1, pilot.power - 1)
	pilot.invulnerable = 3.0
	_start_damage_wave(pilot.pos)
	_add_effect(pilot.pos, "hurt", 24, 0.32)

func _bomb(id: String) -> void:
	var pilot: Dictionary = pilots[id]
	pilot.bombs -= 1
	pilot.invulnerable = maxf(pilot.invulnerable, 2.2)
	_start_damage_wave(pilot.pos)
	_add_effect(pilot.pos, "bomb", 660, 0.85)
	for index: int in range(enemies.size() - 1, -1, -1):
		enemies[index].hp -= 100
		if enemies[index].hp <= 0:
			_destroy_enemy(index)
	if not boss.is_empty() and boss.hp > 0 and boss.telegraph <= 0:
		var damage: float = minf(220, boss.hp)
		boss.hp -= damage
		credit_boss(id, damage)
		if boss.hp <= 0:
			_win()

func _win() -> void:
	if cleared:
		return
	cleared = true
	cleared_stages += 1
	transition_time = 2.2
	if stage_index == STAGE_COUNT:
		state = "won"
	bullets.clear()
	enemies.clear()
	_add_effect(boss.pos, "victory", 360, 2.5)

func _update_shared_pickups(dt: float) -> void:
	for index: int in range(pickups.size() - 1, -1, -1):
		var pickup: Dictionary = pickups[index]
		pickup.age += dt
		pickup.pos.y += 82 * dt
		var claimed: bool = false
		for id: String in pilots:
			var pilot: Dictionary = pilots[id]
			if pilot.lives > 0 and Vector2(pickup.pos).distance_to(pilot.pos) < 25:
				if pickup.type == "bomb":
					pilot.bombs = mini(5, pilot.bombs + 1)
				else:
					pilot.power = mini(4, pilot.power + 1)
				claimed = true
				break
		if claimed or pickup.pos.y > FIELD.y + 35:
			pickups.remove_at(index)

func snapshot() -> Dictionary:
	var result: Dictionary = {"pilots": pilots.duplicate(true), "state": state, "survival": survival, "stage_index": stage_index, "cleared_stages": cleared_stages, "cleared": cleared, "transition_time": transition_time}
	for key: String in ["enemies", "boss", "shots", "bullets", "pickups", "effects", "damage_waves", "cancel_effects"]:
		result[key] = get(key).duplicate(true)
	for bullet: Dictionary in result.bullets:
		bullet.erase("passed_waves")
		bullet.erase("previous")
	return result

func _update_shots(dt: float) -> void:
	for i: Variant in range(shots.size() - 1, -1, -1):
		var shot: Dictionary = shots[i]
		owner = shot.owner
		var previous: Vector2 = shot["pos"]
		var pos: Vector2 = previous + Vector2(shot["vel"]) * dt
		shot["pos"] = pos
		var consumed: Variant = false
		for j: Variant in range(enemies.size() - 1, -1, -1):
			var enemy: Dictionary = enemies[j]
			if _segment_distance_squared(enemy["pos"], previous, pos) < pow(float(enemy["radius"]) + 4.0, 2.0):
				_hit_feedback(enemy, float(shot.damage), shot.vel)
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
					_hit_feedback(boss, float(shot.damage), shot.vel)
					credit_boss(owner, minf(float(boss.hp), float(shot.damage)))
					boss["hp"] = maxf(0.0, float(boss["hp"]) - float(shot["damage"]))
					boss["flash"] = 0.07
					if float(boss["hp"]) <= 0.0:
						_win()
				consumed = true
		if consumed or pos.y < -60.0 or pos.x < -60.0 or pos.x > field_size.x + 60.0:
			shots.remove_at(i)


## Integrate known projectile trajectories locally without resolving gameplay contacts.
func advance_projectile(projectile: Dictionary, dt: float, bullet: bool) -> void:
	var velocity: Vector2 = projectile.vel
	if not bullet:
		projectile.pos += velocity * dt
		return
	var age: float = projectile.age
	var curve: float = projectile.get("angular_velocity", 0.0)
	var curve_dt: float = minf(dt, maxf(0.0, float(projectile.get("curve_duration", 3.0)) - age))
	if projectile.has("speed_end"):
		var travel: float = bullet_travel_at(projectile, age + dt) - bullet_travel_at(projectile, age)
		projectile.pos += velocity.normalized() * travel
		var u: float = clampf((age + dt - float(projectile.accel_delay)) / float(projectile.accel_duration), 0.0, 1.0)
		projectile.vel = velocity.normalized() * lerpf(projectile.speed_start, projectile.speed_end, u * u * (3.0 - 2.0 * u))
	elif absf(curve) > 0.00001 and curve_dt > 0.0:
		var turned: Vector2 = velocity.rotated(curve * curve_dt)
		projectile.pos += Vector2(turned.y - velocity.y, velocity.x - turned.x) / curve + turned * (dt - curve_dt)
		projectile.vel = turned
	else:
		projectile.pos += velocity * dt
	projectile.age = age + dt

func request_bomb(id: String) -> void:
	if state == "playing" and not cleared and pilots.has(id) and pilots[id].lives > 0 and pilots[id].bombs > 0:
		_bomb(id)
