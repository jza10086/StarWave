extends SceneTree
const Core = preload("res://scripts/game_core.gd")
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func run():
	var c = Core.new()
	check(c.field_size == Vector2(1440,960), "full-width baseline")
	check(c.player == Vector2(720,810), "centered start")
	c.start()
	c.player = Vector2(1400,800)
	c.step(.1, Vector2.RIGHT, false, false, false)
	check(c.player.x == 1416, "right edge accessible past old sidebars")
	c.invulnerable = 0
	c._hit_player()
	check(c.player == Vector2(720,810), "respawn centered in new field")
	for variant in range(1,12):
		c.enemies.clear()
		c._spawn_wave(variant)
		var min_x := INF
		var max_x := -INF
		for e in c.enemies:
			check(e.pos.x >= -80 and e.pos.x <= c.field_size.x + 80, "formation enters within bounded outer margin")
			for sample in 32 if e.type=="sniper" else 43:
				var pos: Vector2=c.enemy_route_position(e,2.1+sample*.1)
				min_x=minf(min_x,pos.x)
				max_x=maxf(max_x,pos.x)
				check(pos.x >= 20 and pos.x <= c.field_size.x-20,"attack route stays inside full field")
		if c.enemies.size() >= 3:
			check(min_x <= c.field_size.x*.4 and max_x >= c.field_size.x*.6,"mixed routes cover both field wings")
		else:
			check(max_x-min_x>20,"teaching roles have a readable moving route")
	c.debug_set_boss(3)
	c._add_bullet(Vector2(1100,600),Vector2(150,50),6,Color.WHITE)
	c._spawn_enemy("weaver",Vector2(200,300),0)
	c.resize_field(Vector2(1920,960))
	check(c.field_size == Vector2(1920,960), "wide viewport expands")
	check(c.player == Vector2(960,810) and c.boss.pos.x == 960, "resize remaps player and boss")
	check(is_equal_approx(c.enemies[0].origin_x, c.enemies[0].pos.x), "resize remaps weaving origin")
	check(c.bullets[0].vel == Vector2(150,50) and c.bullets[0].radius == 6, "resize preserves physical bullet speed and radius")
	c.resize_field(Vector2(1440,1440))
	check(c.player == Vector2(720,1215), "tall viewport expands with proportional position")
	c.start()
	check(c.field_size == Vector2(1440,1440) and c.player == Vector2(720,1290), "restart preserves active viewport")
	c.resize_field(Vector2(NAN,960))
	check(c.field_size == Vector2(1440,1440), "invalid viewport rejected")
	c.resize_field(Vector2(1440,960))
	c.debug_set_boss(1)
	c.boss.telegraph = 0.0
	c.boss.choreography_slot = 0
	c.boss.cycle_time = 0.0
	c.player = Vector2(1360,850)
	for i in 110: c.step(1.0/60,Vector2.ZERO,false,false,false)
	var aimed := false
	for b in c.bullets:
		if b.kind == "needle" and b.vel.x > 0: aimed = true
	check(aimed, "aimed boss fire reaches newly playable wings")
	print("FULLWIDTH CORE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
