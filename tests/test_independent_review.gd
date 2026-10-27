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
func fresh():
	var c = Core.new()
	c.start()
	c._next_wave_time = 99999.0
	c.invulnerable = 0.0
	return c
func tick(c, seconds: float, move := Vector2.ZERO, fire := false, focus := false):
	for i in range(int(ceil(seconds * 120))): c.step(1.0/120, move, fire, focus, false)
func run():
	var c = fresh()
	var pos: Vector2 = c.player
	tick(c, .5, Vector2.RIGHT)
	check(is_equal_approx(c.player.x-pos.x,175),"normal movement speed")
	c.player=pos
	tick(c,.5,Vector2.RIGHT,false,true)
	check(absf(c.player.x-pos.x-77.5)<.01 and c.focused,"focus speed and state")
	c.player=pos
	tick(c,.1,Vector2.ONE)
	check(abs(c.player.distance_to(pos)-35)<.01,"diagonal normalized")
	tick(c,5,Vector2(1,1))
	check(c.player.x<=Core.FIELD.x-24 and c.player.y<=Core.FIELD.y-34,"field boundaries")
	c=fresh(); tick(c,.4,Vector2.ZERO,true)
	check(c.shots.size()>=6,"continuous shoot")
	for shot in c.shots: check(shot.vel.y<0,"all shots travel upward")
	c=fresh(); c._add_bullet(c.player+Vector2(15,0),Vector2.ZERO,5,Color.WHITE)
	tick(c,.02)
	check(c.lives==3 and c.graze==1,"wing overlap does not hit, grazes once")
	tick(c,.02)
	check(c.graze==1,"graze cannot farm same bullet")
	c._add_bullet(c.player,Vector2.ZERO,5,Color.WHITE); tick(c,.02)
	check(c.lives==2 and c.bullets.is_empty() and c.invulnerable>2.9,"center hit removes one life, clears bullets, grants invulnerability")
	c._add_bullet(c.player,Vector2.ZERO,5,Color.WHITE); tick(c,.1)
	check(c.lives==2,"invulnerability blocks repeated damage")
	c=fresh(); c._add_bullet(c.player+Vector2(0,-100),Vector2(0,24000),5,Color.WHITE); tick(c,1.0/120)
	check(c.lives==2,"swept projectile collision")
	c=fresh(); c._add_bullet(Vector2(100,100),Vector2.ZERO,5,Color.WHITE)
	c.step(0,Vector2.ZERO,false,false,true)
	check(c.bombs==2 and c.bullets.is_empty() and c.invulnerable>=2.2 and c.score==5,"bomb consumes one, clears, protects, scores")
	c.step(0,Vector2.ZERO,false,false,true)
	check(c.bombs==2,"held bomb latches")
	for i in range(4):
		c.step(0,Vector2.ZERO,false,false,false); c.step(0,Vector2.ZERO,false,false,true)
	check(c.bombs==0,"bomb limit never negative")
	c=fresh(); c._spawn_enemy("scout",Vector2(360,500),0); c.enemies[0].hp=5
	c._add_shot(Vector2(360,510),Vector2(0,-950),5); tick(c,1.0/120)
	check(c.kills==1 and c.score==250 and c.enemies.is_empty() and c.pickups.size()==1,"kill scoring and drop")
	c=fresh(); c.power=4; c.bombs=5
	c._add_pickup(c.player,"power"); c._add_pickup(c.player,"bomb"); tick(c,.01)
	check(c.power==4 and c.bombs==5,"resource pickup caps")
	c.score=25000; tick(c,.01); check(c.lives==4,"extend awarded")
	tick(c,.01); check(c.lives==4,"extend awarded only once")
	c=Core.new(); c.start(); c.invulnerable=999
	tick(c,86.2)
	check(c.wave==12 and not c.boss.is_empty() and c.enemies.is_empty(),"natural progression to boss")
	for phase in [1,2,3]:
		c.debug_set_boss(phase); c.invulnerable=999
		tick(c,1)
		check(c.bullets.is_empty(),"phase %d warning gives safe gap"%phase)
		tick(c,4) # Include the scheduled ring after the locked-aim opening.
		check(c.bullets.size()>10 and c.boss.phase==phase,"phase %d emits bullets"%phase)
	c.debug_set_boss(); c.boss.telegraph=0; c.boss.hp=1599
	c._add_bullet(Vector2(100,100),Vector2.ZERO,5,Color.WHITE); tick(c,.01)
	check(c.boss.phase==2 and c.bullets.is_empty() and c.boss.telegraph>1.7,"phase transition clears and warns")
	c.debug_set_boss(3); c.boss.telegraph=0; c.boss.hp=1
	c._add_shot(c.boss.pos,Vector2.ZERO,5); tick(c,.01)
	check(c.state=="won" and c.bullets.is_empty(),"boss kill wins")
	var score: int=c.score; tick(c,1)
	check(c.score==score,"win score not repeated")
	c=fresh(); c.lives=1; c._hit_player(); var elapsed:float=c.elapsed; tick(c,1)
	check(c.state=="lost" and c.lives==0 and c.elapsed==elapsed,"loss freezes simulation")
	c.start(); check(c.state=="playing" and c.lives==3 and c.bombs==3 and c.elapsed==0 and c.boss.is_empty() and c.bullets.is_empty(),"restart resets terminal state")
	c=fresh()
	for i in range(2000): c._add_bullet(Vector2(100,100),Vector2.ZERO,5,Color.WHITE)
	check(c.bullets.size()==900,"bullet cap")
	for bullet in c.bullets: bullet.age=28.1
	tick(c,.01); check(c.bullets.is_empty(),"expired bullet cleanup")
	c.debug_set_boss(3); c.invulnerable=999; tick(c,60)
	check(c.bullets.size()<=900 and c.effects.size()<=90 and c.shots.size()<=220,"long dense boss bounds")
	print("INDEPENDENT REVIEW: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
