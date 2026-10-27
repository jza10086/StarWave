extends SceneTree

const Core = preload("res://scripts/game_core.gd")
var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func tick(core, seconds: float, fire: bool = false, direction: Vector2 = Vector2.ZERO) -> void:
	for _i in range(int(ceil(seconds * 60.0))):
		core.step(1.0 / 60.0, direction, fire, false, false)

func _run() -> void:
	var c = Core.new()
	check(c.state == "ready" and c.lives == 3 and c.bombs == 3, "ready defaults")
	c.step(1.0, Vector2.ONE, true, false, true)
	check(c.elapsed == 0.0 and c.shots.is_empty(), "ready does not advance")
	c.start()
	c.step(1.0 / 60.0, Vector2.ZERO, true, false, false)
	check(c.shots.size() == 2, "shoots two upward bullets at power one")
	check(c.shots[0]["vel"].y < 0.0, "shots travel upward")
	var before: Vector2 = c.player
	c.step(0.1, Vector2(1.0, 0.0), false, false, false)
	var fast: float = c.player.x - before.x
	before = c.player
	c.step(0.1, Vector2(1.0, 0.0), false, true, false)
	check(c.player.x - before.x < fast * 0.5, "focus lowers movement speed")
	c.step(900.0, Vector2.ONE, false, false, false)
	check(c.elapsed < 0.5, "delta is safely capped")
	c.step(NAN, Vector2.ZERO, false, false, false)
	check(is_finite(c.elapsed), "nonfinite delta rejected")
	c.step(0.1, Vector2(NAN, INF), false, false, false)
	check(c.player.is_finite(), "nonfinite input sanitized")
	c.player = Vector2(-999.0, 9999.0)
	c.step(0.1, Vector2.ZERO, false, false, false)
	check(c.player.x >= 24.0 and c.player.y <= Core.FIELD.y - 34.0, "player stays within field")
	c.start()
	c.invulnerable = 0.0
	for _i in range(12):
		c.bullets.append({"pos": c.player, "vel": Vector2.ZERO, "radius": 6.0})
	c.step(0.1, Vector2.ZERO, false, false, false)
	check(c.lives == 2 and c.invulnerable > 2.8 and c.bullets.is_empty(), "one hit per frame with safe respawn")
	c.invulnerable = 0.0
	c.bullets.append({"pos": c.player + Vector2(0.0, -300.0), "vel": Vector2(0.0, 72000.0), "radius": 6.0})
	c.step(1.0 / 60.0, Vector2.ZERO, false, false, false)
	check(c.lives == 1, "swept collision catches fast bullet")
	c.invulnerable = 0.0
	c.bullets.append({"pos": c.player, "vel": Vector2.ZERO, "radius": 6.0})
	c.step(0.1, Vector2.ZERO, false, false, false)
	check(c.state == "lost" and c.lives == 0, "last life ends game")
	c.start()
	c._spawn_enemy("gunner", Vector2(360.0, 200.0), 0)
	c.bullets.append({"pos": c.player, "vel": Vector2.ZERO, "radius": 6.0})
	c.step(0.1, Vector2.ZERO, false, false, true)
	check(c.bombs == 2 and c.bullets.is_empty() and c.enemies.is_empty(), "bomb clears and destroys enemies")
	c.step(0.1, Vector2.ZERO, false, false, true)
	check(c.bombs == 2, "holding bomb does not consume repeatedly")
	c.step(0.0, Vector2.ZERO, false, false, false)
	c.step(0.0, Vector2.ZERO, false, false, true)
	check(c.bombs == 1, "zero-delta input-only bomb supported")
	c.step(0.01, Vector2.ZERO, false, false, false)
	c.bombs = 0
	c.step(0.01, Vector2.ZERO, false, false, true)
	check(c.bombs == 0, "no bomb count underflow")
	c.pickups.clear()
	c.pickups.append({"pos": c.player, "type": "power", "age": 0.0})
	c.step(0.01, Vector2.ZERO, false, false, false)
	check(c.power == 2 and c.pickups.is_empty(), "power pickup upgrades weapons")
	c.power = 4
	c.pickups.append({"pos": c.player, "type": "power", "age": 0.0})
	c.step(0.01, Vector2.ZERO, false, false, false)
	check(c.power == 4, "power cap")
	c.debug_set_boss()
	tick(c, 0.8)
	check(c.bullets.is_empty(), "boss opening has no surprise bullets")
	tick(c, 1.0)
	check(c.bullets.size() > 0, "boss starts patterned fire after telegraph")
	c.boss["hp"] = 1550.0
	c.step(0.01, Vector2.ZERO, false, false, false)
	check(c.boss["phase"] == 2 and c.bullets.is_empty() and c.boss["telegraph"] > 1.7, "phase two clears field and telegraphs")
	c.boss["hp"] = 760.0
	c.step(0.01, Vector2.ZERO, false, false, false)
	check(c.boss["phase"] == 3 and c.boss["telegraph"] > 1.7, "phase three telegraphs")
	c.boss["telegraph"] = 0.0
	c.boss["hp"] = 5.0
	c.shots.append({"pos": c.boss["pos"] + Vector2(0.0, 1.0), "vel": Vector2(0.0, -900.0), "damage": 10.0, "radius": 4.0})
	c.step(0.01, Vector2.ZERO, false, false, false)
	check(c.state == "won" and c.boss["hp"] == 0.0, "boss defeat completes mission")
	c.start()
	check(c.boss.is_empty() and c.lives == 3 and c.score == 0 and c.wave == 0, "restart restores clean state")
	var a = Core.new()
	var b = Core.new()
	a.start()
	b.start()
	var observed: Dictionary = {}
	var peak_bullets: int = 0
	for i in range(120 * 60):
		var dir := Vector2(sin(i * 0.015), cos(i * 0.009) * 0.2)
		a.invulnerable = 999.0
		b.invulnerable = 999.0
		a.step(1.0 / 60.0, dir, false, i % 500 < 250, false)
		b.step(1.0 / 60.0, dir, false, i % 500 < 250, false)
		peak_bullets = maxi(peak_bullets, a.bullets.size())
		for enemy in a.enemies:
			observed[enemy["type"]] = true
	# The stage now teaches three additional movement/attack roles.
	check(observed.size() == 6, "all six taught enemy archetypes appear")
	check(not a.boss.is_empty() and a.wave == 12, "full timeline reaches boss")
	check(a.player == b.player and a.score == b.score and a.bullets == b.bullets and a.boss == b.boss, "simulation repeatable with identical input")
	check(peak_bullets <= Core.MAX_BULLETS and a.shots.size() <= Core.MAX_SHOTS and a.enemies.size() <= Core.MAX_ENEMIES, "bounded entity storage")
	# Boss patterns remain bounded through a long no-damage soak.
	a.debug_set_boss(3)
	for i in range(120 * 60):
		a.invulnerable = 999.0
		a.step(1.0 / 60.0, Vector2.ZERO, false, true, false)
		peak_bullets = maxi(peak_bullets, a.bullets.size())
	check(a.bullets.size() <= Core.MAX_BULLETS and a.effects.size() <= Core.MAX_EFFECTS, "final-phase soak stays bounded")
	# Full-length firing pass validates that the authored stage is actually beatable.
	# Shielding isolates progression/DPS from autopilot dodge quality.
	c.start()
	for _i in range(180 * 60):
		c.invulnerable = 999.0
		var target_x: float = Core.FIELD.x * 0.5
		if not c.boss.is_empty():
			target_x = c.boss["pos"].x
		elif not c.enemies.is_empty():
			target_x = c.enemies[0]["pos"].x
		var dx: float = clampf((target_x - c.player.x) / 25.0, -1.0, 1.0)
		c.step(1.0 / 60.0, Vector2(dx, 0.0), true, true, false)
		if c.state != "playing":
			break
	check(c.state == "won", "full-stage firing run reaches victory")
	check(c.elapsed > Core.BOSS_TIME and c.elapsed < 180.0, "mission pacing under three minutes")
	var victory_time: float = c.elapsed
	c.debug_set_boss(3)
	c.boss["telegraph"] = 0.0
	c.boss["hp"] = 100.0
	c.step(0.0, Vector2.ZERO, false, false, true)
	check(c.state == "won" and c.last_event == "victory", "bomb can finish boss and preserves victory event")
	c.start()
	c.invulnerable = 0.0
	c.bullets.append({"pos": c.player + Vector2(20.0, 0.0), "vel": Vector2.ZERO, "radius": 5.0})
	tick(c, 0.1)
	check(c.lives == 3 and c.graze == 1 and c.score == 20, "graze rewards once outside tiny hitbox")
	var frozen_time: float = c.elapsed
	c.state = "lost"
	c.step(0.1, Vector2.ONE, true, false, true)
	check(c.elapsed == frozen_time, "terminal state freezes simulation")
	print("FULL SHOOTING RUN: %.1f seconds to victory" % victory_time)
	print("CORE TESTS: %d checks, %d failures; peak bullets=%d" % [checks, failures, peak_bullets])
	quit(1 if failures > 0 else 0)
