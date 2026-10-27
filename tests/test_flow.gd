extends SceneTree
## Combat-flow regression and normal-input observation, not a human difficulty guarantee.
const Core = preload("res://scripts/game_core.gd")
const Pilot = preload("res://tests/test_patterns.gd")
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func normal_play(size: Vector2, label: String):
	var c = Core.new()
	c.resize_field(size)
	c.start()
	var peak := 0
	var peak_enemies := 0
	var used := 0
	var dir := Vector2.ZERO
	var close_births := 0
	var overlapping_waves := 0
	var wave_seen := 0
	var worst_open_lanes := 17
	var edge_seconds := 0.0
	var transitions: Array = []
	for frame in 60*240:
		if c.state != "playing": break
		if frame%6 == 0: dir = Pilot.steer(c)
		var danger := false
		if c.invulnerable <= 0 and frame%2 == 0:
			for b in c.bullets:
				if Core._segment_distance_squared(c.player,b.pos,b.pos+b.vel*.18) < pow(float(b.radius)+15,2): danger = true; break
		var before: int = c.bombs
		c.step(1.0/60,dir,true,false,danger)
		used += maxi(0,before-c.bombs)
		peak = maxi(peak,c.bullets.size())
		peak_enemies = maxi(peak_enemies,c.enemies.size())
		if c.player.x < 90 or c.player.x > c.field_size.x-90: edge_seconds += 1.0/60
		for b in c.bullets:
			if float(b.age) <= 1.0/60 and Vector2(b.get("origin",b.pos)).distance_to(c.player) < 130: close_births += 1
		if c.wave != wave_seen:
			if c.bullets.size() > 0: overlapping_waves += 1
			transitions.append([c.wave,snappedf(c.elapsed,.01),c.bullets.size()])
			wave_seen=c.wave
		if frame%30 == 0:
			var open := 0
			for lane in 17:
				var point := Vector2(60+(c.field_size.x-120)*lane/16.0,c.player.y)
				var clear := true
				for b in c.bullets:
					if Core._segment_distance_squared(point,b.pos,b.pos+b.vel*.4) < pow(float(b.radius)+Core.PLAYER_RADIUS+12,2): clear=false; break
				if clear: open += 1
			worst_open_lanes=mini(worst_open_lanes,open)
	print("FLOW_AUTOPLAY label=",label," field=",size," state=",c.state," elapsed=",snappedf(c.elapsed,.01)," lives=",c.lives," bombs_used=",used," power=",c.power," kills=",c.kills," peak_bullets=",peak," peak_enemies=",peak_enemies," close_births=",close_births," residual_wave_transitions=",overlapping_waves," min_sampled_open_lanes=",worst_open_lanes," edge_seconds=",snappedf(edge_seconds,.01)," boss_hp=",c.boss.get("hp",-1))
	print("FLOW_WAVE_TRANSITIONS ",label," ",transitions)
	check(c.state == "won","normal-input full-stage win "+label)
	check(peak < Core.MAX_BULLETS and peak_enemies < Core.MAX_ENEMIES,"bounded normal run "+label)
	check(close_births == 0,"no point-blank births "+label)
	check(worst_open_lanes > 0,"sampled player row never completely sealed "+label)

func role_and_phrase_checks():
	var c = Core.new()
	c.start()
	c._boss_spawned=true
	for kind in ["sniper","sweeper","gunner"]:
		c.enemies.clear()
		c.bullets.clear()
		c._spawn_enemy(kind,Vector2(720,210),0)
		var e: Dictionary = c.enemies[0]
		e.age=3.0
		e.stage="attack"
		e.attack_allowed=true
		c._enemy_fire(e)
		check(not c.bullets.is_empty(),"functional role emits "+kind)
		for bullet in c.bullets:
			if bullet.kind=="needle": check(bullet.radius<=4 and bullet.vel.length()>=260,"small fast needle")
			elif bullet.kind=="crescent": check(bullet.radius>=9 and bullet.vel.length()<=120,"large slow obstacle")
			else: check(bullet.radius>=5 and bullet.radius<=7 and bullet.vel.length()>=150 and bullet.vel.length()<=200,"medium stream")
	var a=Core.new()
	var b=Core.new()
	for test in [a,b]:
		test.start()
		test._add_accelerating_bullet(Vector2(100,100),Vector2.DOWN,110,280)
	for i in 31: a._update_bullets(.1)
	for i in 372: b._update_bullets(1.0/120)
	check(a.bullets[0].pos.distance_to(b.bullets[0].pos)<.02,"accelerating trajectory 10/120Hz exact integration")
	check(absf(a.bullets[0].vel.length()-280)<.001,"accelerating bullet reaches capped speed")
	check(absf(Core.bullet_travel_at(a.bullets[0],.8)-88)<.001,"acceleration preserves .8s slow lead-in")
	for phase in [1,2,3]:
		c.debug_set_boss(phase)
		var phrases: Dictionary={}
		var rest_births:=0
		var attack_motion:=0.0
		var previous: Vector2=c.boss.pos
		for frame in 60*17:
			c.step(1.0/60,Vector2.ZERO,false,false,false)
			var phrase: String=c.boss.get("phrase","")
			phrases[phrase]=true
			if phrase in ["blades","curves"]: attack_motion=maxf(attack_motion,previous.distance_to(c.boss.pos))
			if phrase=="rest":
				for bullet in c.bullets:
					if bullet.age <= 1.0/60: rest_births+=1
			previous=c.boss.pos
		check(phrases.has_all(["reposition","blades","curves","spiral","expand","rest"]),"all boss phrases phase "+str(phase))
		check(attack_motion<.001,"boss holds position during attacks phase "+str(phase))
		check(rest_births==0,"boss rest has no fresh emissions phase "+str(phase))

func run():
	role_and_phrase_checks()
	var capped=Core.new()
	capped.debug_set_boss(2)
	for i in Core.MAX_BULLETS:
		capped._add_bullet(Vector2(100,100),Vector2.DOWN*170,6,Core.PURPLE)
	var existing: Array=capped.bullets.duplicate(true)
	capped._boss_radial_ring(36,0,180,Core.PURPLE,.055)
	check(capped.bullets.size()==Core.MAX_BULLETS,"capped boss ring cannot overflow")
	check(capped.bullets==existing,"capped boss ring cannot mutate existing bullet trajectory")
	# Core's inactive state is the pause contract; UI pause is verified in real renders.
	var a = Core.new()
	var b = Core.new()
	a.debug_set_boss(3)
	b.debug_set_boss(3)
	for i in 30*12: a.step(1.0/30,Vector2.ZERO,false,false,false)
	for i in 120*12: b.step(1.0/120,Vector2.ZERO,false,false,false)
	check(a.bullets.size()==b.bullets.size(),"12s 30/120Hz emission counts")
	check(a.boss.pos.distance_to(b.boss.pos)<.001,"12s 30/120Hz boss path")
	var invariant: bool = a.bullets.size()==b.bullets.size()
	for i in mini(a.bullets.size(),b.bullets.size()):
		if a.bullets[i].pos.distance_to(b.bullets[i].pos)>.002: invariant=false
	check(invariant,"12s 30/120Hz bullet paths")
	var saved := [a.elapsed,a.boss.duplicate(true),a.bullets.duplicate(true)]
	a.state="ready"
	a.step(.1,Vector2.ONE,true,true,true)
	check([a.elapsed,a.boss,a.bullets]==saved,"inactive state freezes complete combat state")
	a.start()
	check(a.boss.is_empty() and a.bullets.is_empty() and a.enemies.is_empty() and a.elapsed==0 and a.wave==0,"restart clears route and phrase state")
	var interrupted=Core.new()
	interrupted.debug_set_boss(1)
	for frame in 60*5: interrupted.step(1.0/60,Vector2.ZERO,false,false,false)
	interrupted.boss.hp=1500.0
	var maximum_jump:=0.0
	for frame in 60*12:
		var before: Vector2=interrupted.boss.pos
		interrupted.step(1.0/60,Vector2.ZERO,false,false,false)
		maximum_jump=maxf(maximum_jump,before.distance_to(interrupted.boss.pos))
	print("FLOW_BOSS_MAX_STEP ",maximum_jump)
	check(maximum_jump<9,"phase interruption and cycle restart preserve boss movement continuity")
	# A boss arrival must clear residual previous-wave bullets in tall fields too.
	for size in [Vector2(1440,960),Vector2(1440,1800)]:
		var c = Core.new()
		c.resize_field(size)
		c.start()
		c._add_bullet(Vector2(400,700),Vector2.DOWN*90,10,Core.GOLD)
		c._spawn_enemy("scout",Vector2(500,100),0)
		c.elapsed=Core.BOSS_TIME
		c._update_stage()
		check(c.enemies.is_empty() and c.bullets.is_empty(),"boss arrival clears residual waves "+str(size))
	normal_play(Vector2(1706.666667,960),"landscape1920x1080")
	normal_play(Vector2(1440,1800),"portrait800x1000")
	normal_play(Vector2(1440,960),"small960x640")
	print("FLOW ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
