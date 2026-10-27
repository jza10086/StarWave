extends SceneTree
const Core = preload("res://scripts/game_core.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1; push_error(label)
func _initialize(): call_deferred("run")
func run():
	for size in [Vector2(1440,960),Vector2(1706.6667,960),Vector2(1440,1800)]:
		for kind in ["scout","gunner","weaver","sniper","sweeper","orbiter"]:
			var c = Core.new()
			c.resize_field(size)
			c.start()
			c._boss_spawned = true
			c._spawn_enemy(kind,Vector2(size.x*.5,-48),0)
			var e: Dictionary = c.enemies[0]
			check(c.enemy_route_position(e,0).distance_to(e.pos)<.001,"route begins exactly at spawn "+kind)
			for join in [2.1,5.4 if kind == "sniper" else 6.4]:
				var before: Vector2 = c.enemy_route_position(e,join-.001)
				var at: Vector2 = c.enemy_route_position(e,join)
				var after: Vector2 = c.enemy_route_position(e,join+.001)
				check(before.distance_to(after)<1,"continuous join "+kind)
				check(((at-before)-(after-at)).length()/.001<3,"continuous tangent "+kind)
			var previous: Vector2 = e.pos
			var seen := {}
			var peak_bank := 0.0
			for frame in range(1060):
				c._update_enemies(1.0/120)
				if c.enemies.is_empty(): break
				seen[e.stage] = true
				peak_bank = maxf(peak_bank,absf(e.rotation))
				check(e.pos.is_finite() and e.pos.distance_to(previous)<9,"bounded finite route step "+kind)
				if e.stage != "attack": check(not e.attack_allowed,"entry/exit gated "+kind)
				previous = e.pos
			check(seen.size()==3 and c.enemies.is_empty(),"complete lifecycle "+kind)
			check(peak_bank>.02 and peak_bank<=.301,"modest motion-derived bank "+kind)
	var c = Core.new()
	c._spawn_enemy("orbiter",Vector2(600,-48),0)
	var e: Dictionary = c.enemies[0]
	e.age = 3.3
	e.pos = c.enemy_route_position(e,e.age)
	c.resize_field(Vector2(1800,1200))
	check(e.pos.distance_to(c.enemy_route_position(e,e.age))<.001,"resize maps the entire path without snap")
	var a = Core.new()
	var b = Core.new()
	for game in [a,b]: game.start(); game._boss_spawned=true; game._spawn_enemy("sweeper",Vector2(600,-48),0)
	for i in 120: a.step(1.0/30,Vector2.ZERO,false,false,false)
	for i in 480: b.step(1.0/120,Vector2.ZERO,false,false,false)
	check(a.enemies[0].pos.distance_to(b.enemies[0].pos)<.001,"route timestep invariance")
	check(absf(a.enemies[0].rotation-b.enemies[0].rotation)<.001,"bank timestep invariance")
	print("ROUTES ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
