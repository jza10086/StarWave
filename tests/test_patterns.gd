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
func advance(c, seconds: float, dt := 1.0/60.0):
	for i in int(round(seconds/dt)): c.step(dt,Vector2.ZERO,false,false,false)

# A deterministic reactive controller: normal input only, no health/power/timer edits.
# It observes current bullet velocity, chooses a short safe movement and shoots upward.
static func steer(c) -> Vector2:
	var target := Vector2(c.field_size.x*.5,c.field_size.y-180)
	if not c.boss.is_empty(): target.x = c.boss.pos.x
	elif not c.enemies.is_empty():
		var nearest := INF
		for e in c.enemies:
			if e.pos.y > 0 and e.pos.y < c.player.y-100:
				var distance: float = absf(e.pos.x-c.player.x)
				if distance < nearest:
					nearest = distance
					target.x = e.pos.x
	for p in c.pickups:
		if p.type == "power" and p.pos.y > c.field_size.y*.5 and p.pos.distance_to(c.player) < 300:
			target = p.pos
	var desired: Vector2 = (target-c.player).limit_length(1)
	var choices := [Vector2.ZERO,desired,Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN,Vector2(-1,-1).normalized(),Vector2(1,-1).normalized(),Vector2(-1,1).normalized(),Vector2(1,1).normalized()]
	var best := Vector2.ZERO
	var best_cost := INF
	for dir in choices:
		var future: Vector2 = c.player+dir*Core.PLAYER_SPEED*.4
		var cost: float = future.distance_to(target)*.025
		if future.x < 65 or future.x > c.field_size.x-65 or future.y < 320 or future.y > c.field_size.y-65: cost += 1000
		for b in c.bullets:
			if b.pos.distance_squared_to(c.player) > 400*400: continue
			var relative: Vector2 = b.vel-dir*Core.PLAYER_SPEED
			var offset: Vector2 = b.pos-c.player
			var t := clampf(-offset.dot(relative)/maxf(relative.length_squared(),1),0,.65)
			var distance := (offset+relative*t).length()-float(b.radius)-Core.PLAYER_RADIUS
			if distance < 55: cost += pow(maxf(0,55-distance),2)*(.04 if c.invulnerable > .5 else 1.0)
		for e in c.enemies:
			var distance: float = future.distance_to(e.pos)-e.radius
			if distance < 100: cost += pow(100-distance,2)
		if cost < best_cost:
			best_cost = cost
			best = dir
	return best

func play_stage(size: Vector2):
	var c = Core.new()
	c.resize_field(size)
	c.start()
	var peak := 0
	var used := 0
	var dir := Vector2.ZERO
	for frame in 60*230:
		if c.state != "playing": break
		if frame%6 == 0: dir = steer(c)
		var danger := false
		if c.invulnerable <= 0 and frame%2 == 0:
			for b in c.bullets:
				if Core._segment_distance_squared(c.player,b.pos,b.pos+b.vel*.18) < pow(float(b.radius)+15,2): danger = true; break
		var before: int = c.bombs
		c.step(1.0/60,dir,true,false,danger)
		used += maxi(0,before-c.bombs)
		peak = maxi(peak,c.bullets.size())
	print("AUTOPLAY field=",size," state=",c.state," elapsed=",snappedf(c.elapsed,.01)," lives=",c.lives," bombs=",c.bombs," bombs_used=",used," power=",c.power," kills=",c.kills," peak_bullets=",peak," boss_hp=",c.boss.get("hp",-1))
	check(c.state == "won","normal-input automated full-stage win "+str(size))
	check(peak < Core.MAX_BULLETS,"normal run stays below bullet cap")

func run():
	for kind in ["sniper","sweeper","orbiter"]:
		var c = Core.new()
		c.start()
		c._boss_spawned = true
		c._spawn_enemy(kind,Vector2(600,180),0)
		var e: Dictionary = c.enemies[0]
		check(e.type == kind and e.hp > 0,"new role spawn "+kind)
		advance(c,1.0)
		check(e.pos.is_finite(),"finite role movement "+kind)
		advance(c,6.0)
		check(c.bullets.size() > 0,"role emits bullets "+kind)
		check(c.bullets.size() < 120,"role bounded burst "+kind)
		c.bullets.clear()
		c._enemy_fire(e)
		check(c.bullets.is_empty(),"retreat stops emission "+kind)
		advance(c,2.1)
		check(c.enemies.is_empty(),"role retreats and cleans up "+kind)
	var a = Core.new()
	var b = Core.new()
	a.debug_set_boss(2)
	b.debug_set_boss(2)
	advance(a,4,1.0/30)
	advance(b,4,1.0/120)
	check(absf(a.boss.rotation-b.boss.rotation)<.0001,"rotation simulation timestep invariant 30/120 Hz")
	check(absf(a.boss.rotation)> .1,"boss visibly rotates")
	check(a.bullets.size()==b.bullets.size(),"choreography timestep emission count")
	var same_paths: bool = a.bullets.size()==b.bullets.size()
	for i in mini(a.bullets.size(),b.bullets.size()):
		if a.bullets[i].pos.distance_to(b.bullets[i].pos)>.001: same_paths=false
	check(same_paths,"curved projectile positions invariant at 30/120 Hz")
	var held: float = a.boss.rotation
	a.state = "ready"
	a.step(.1,Vector2.ZERO,false,false,false)
	check(a.boss.rotation==held,"inactive simulation freezes rotation")
	a.start()
	check(a.boss.is_empty() and a.elapsed==0,"restart clears rotation and choreography")
	a._spawn_boss()
	check(a.boss.rotation == 0,"new boss resets rotation")
	# Locked warnings remain fixed even when the player crosses to the other side.
	var locked = Core.new()
	locked.start()
	locked._boss_spawned = true
	locked._spawn_enemy("sniper",Vector2(720,210),0)
	advance(locked,.75)
	var enemy: Dictionary = locked.enemies[0]
	var angle: float = enemy.warning_angle
	check(enemy.telegraph > 0 and locked.bullets.is_empty(),"sniper warning precedes emission")
	locked.player.x = 1100
	advance(locked,.25)
	check(enemy.warning_angle==angle,"sniper aim does not track during warning")
	advance(locked,.5)
	check(not locked.bullets.is_empty() and absf(locked.bullets[1].vel.angle()-angle)<.001,"sniper shoots locked aim")
	var roles = Core.new()
	roles.start()
	for kind in ["sweeper","orbiter"]:
		roles.enemies.clear()
		roles.bullets.clear()
		roles._spawn_enemy(kind,Vector2(720,210),0)
		roles._enemy_fire(roles.enemies[0])
		var gap := true
		for bullet in roles.bullets:
			if absf(wrapf(bullet.vel.angle()-(PI*.5-.12 if kind=="sweeper" else PI*.5),-PI,PI))<.30: gap=false
		check(gap,"open escape lane "+kind)
	roles.bullets.clear()
	roles.player = roles.enemies[0].pos+Vector2(0,40)
	roles._enemy_fire(roles.enemies[0])
	check(roles.bullets.is_empty(),"point blank ordinary emission suppressed")
	var curved = Core.new()
	curved.debug_set_boss(2)
	curved.boss.rotation = .73
	for blade in 6:
		curved.bullets.clear()
		curved._boss_fan(blade,PI*.5,1,.1,150,Core.GOLD,5,"orb",.065)
		check(curved.bullets[0].pos.distance_to(curved.boss.pos+Core.blade_tip_offset(blade,.73))<.001,"emission matches rotating blade tip "+str(blade))
	var bullet: Dictionary = curved.bullets[0]
	var start: Vector2 = bullet.pos
	var velocity: Vector2 = bullet.vel
	for i in 120: curved._update_bullets(1.0/120)
	check(absf(bullet.vel.angle()-velocity.angle())>.06,"boss bullet velocity actually curves")
	check(bullet.pos.distance_to(start+velocity)>4,"curved trajectory differs from straight wake")
	check(absf(bullet.vel.length()-velocity.length())<.01,"curved projectile preserves speed")
	for i in 246: curved._update_bullets(1.0/120)
	var tangent: Vector2 = bullet.vel
	var tangent_start: Vector2 = bullet.pos
	curved._update_bullets(.1)
	check(bullet.vel.distance_to(tangent)<.001,"curvature stops after three seconds")
	check(bullet.pos.distance_to(tangent_start+tangent*.1)<.001,"portrait-safe tangent continuation")
	var boundary_a = Core.new()
	var boundary_b = Core.new()
	for boundary in [boundary_a,boundary_b]:
		boundary.start()
		boundary._add_bullet(Vector2(100,100),Vector2(0,100),5,Core.GOLD,"orb",.12)
	for i in 31: boundary_a._update_bullets(.1)
	for i in 372: boundary_b._update_bullets(1.0/120)
	print("ARC_BOUNDARY_ERROR ",boundary_a.bullets[0].pos.distance_to(boundary_b.bullets[0].pos))
	check(boundary_a.bullets[0].pos.distance_to(boundary_b.bullets[0].pos)<.02,"arc/tangent boundary invariant within .02px at 10/120 Hz")
	var slowest := INF
	var fastest := 0.0
	var previous_speed := 0.0
	var smooth := true
	curved.debug_set_boss(1)
	for i in 60*9:
		curved.step(1.0/60,Vector2.ZERO,false,false,false)
		var speed: float = absf(curved.boss.rotation_speed)
		if i>0 and absf(speed-previous_speed)>.05: smooth=false
		slowest=minf(slowest,speed)
		fastest=maxf(fastest,speed)
		previous_speed=speed
	check(fastest>slowest*2,"attack rotation accelerates beyond rest speed")
	check(smooth,"rotation speed eases without abrupt jumps")
	play_stage(Vector2(1440,960))
	play_stage(Vector2(1440,1800))
	print("PATTERNS ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
