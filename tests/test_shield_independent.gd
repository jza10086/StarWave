extends SceneTree
## Independent boundary fixtures: no scene/art assumptions and no production input edits.
const Core = preload("res://scripts/game_core.gd")
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool,label: String):
	checks += 1
	if not ok:
		failures += 1
		push_error("INDEPENDENT SHIELD: "+label)
func near(actual: float,expected: float,label: String):
	check(absf(actual-expected)<.00001,label+" actual="+str(actual))
func fresh():
	var c = Core.new()
	c.start()
	c._boss_spawned = true
	c.invulnerable = 0.0
	return c
func tick(c, seconds: float, dir := Vector2.ZERO, dt := 1.0/120):
	for i in int(round(seconds/dt)): c.step(dt,dir,false,false,false)
func count_id(c,id: int) -> int:
	var total := 0
	for b in c.bullets:
		if b.get("fixture_id",-1)==id: total += 1
	return total
func tagged(c,p: Vector2,v: Vector2,id: int):
	c._add_bullet(p,v,5,Core.PINK)
	c.bullets.back()["fixture_id"]=id
func run():
	near(Core.swept_wave_time(Vector2(15,0),Vector2(15,0),Vector2.ZERO,10,20,1),.4,"stationary moving-front contact")
	near(Core.swept_wave_time(Vector2(-100,0),Vector2(100,0),Vector2.ZERO,10,10,0),.45,"outside-to-outside tunnelling")
	near(Core.swept_wave_time(Vector2(-100,10),Vector2(100,10),Vector2.ZERO,10,10,0),.5,"tangent contact")
	near(Core.swept_wave_time(Vector2(25,0),Vector2(15,0),Vector2.ZERO,10,20,0),.75,"linear quadratic degeneracy")
	near(Core.swept_wave_time(Vector2(100,0),Vector2(100,0),Vector2.ZERO,10,200,0),90.0/190,"negative quadratic coefficient")
	near(Core.swept_wave_time(Vector2(20,0),Vector2(10,0),Vector2.ZERO,10,10,0),1,"endpoint contact")
	near(Core.swept_wave_time(Vector2.ZERO,Vector2.ZERO,Vector2.ZERO,10,20,4),0,"initial overlap")
	check(Core.swept_wave_time(Vector2(20,0),Vector2(100,0),Vector2.ZERO,10,50,0)<0,"bullet outruns finite wave")
	check(Core.swept_wave_time(Vector2(-100,11),Vector2(100,11),Vector2.ZERO,10,10,0)<0,"near tangent miss")
	var c = fresh()
	c.player=Vector2(500,500)
	var origin: Vector2=c.player
	for i in 4: tagged(c,origin+Vector2([10,200,600,1000][i],0),Vector2.ZERO,i)
	c._hit_player()
	check(c.bullets.size()==4,"damage itself does not instant-clear distant field")
	check(c.damage_waves.size()==1 and c.damage_waves[0].pos==origin,"fixed origin captured before respawn")
	check(c.player!=origin and c.lives==2 and c.invulnerable==3,"respawn and protection preserved")
	tick(c,.2,Vector2.RIGHT)
	check(count_id(c,0)==0 and count_id(c,1)==0 and count_id(c,2)==1 and count_id(c,3)==1,"front clears only reached distances")
	check(c.damage_waves[0].pos==origin,"player motion does not tow wave")
	near(c.damage_waves[0].radius,Core.damage_wave_radius(c.damage_waves[0]),"shared visual and collision radius")
	tick(c,.1)
	check(count_id(c,2)==0 and count_id(c,3)==1,"middle distance cleared later than near distance")
	tick(c,.3)
	check(c.bullets.is_empty() and c.damage_waves.is_empty(),"last swept interval reaches retained offscreen bullet and expires")
	tick(c,.3)
	check(c.cancel_effects.is_empty() and c._cancel_pool.size()<=Core.MAX_CANCEL_EFFECTS,"remnants expire into bounded pool")
	# Reverse iteration must not leave a previously visited near bullet visibly live.
	for reversed_order in [false,true]:
		c=fresh()
		var hit: Vector2=c.player
		if reversed_order:
			tagged(c,hit+Vector2(15,0),Vector2.ZERO,20)
			tagged(c,hit,Vector2.ZERO,21)
		else:
			tagged(c,hit,Vector2.ZERO,21)
			tagged(c,hit+Vector2(15,0),Vector2.ZERO,20)
		c.step(1.0/120,Vector2.ZERO,false,false,false)
		check(c.lives==2 and c.bullets.is_empty() and c.cancel_effects.size()==2,"same-tick initial sweep is index-order safe "+str(reversed_order))
	# High-speed path enters/exits the same wave during a single physics tick.
	c=fresh(); c._start_damage_wave(Vector2(720,400))
	tagged(c,Vector2(620,400),Vector2(24000,0),1)
	c.invulnerable=1
	c.step(1.0/120,Vector2.ZERO,false,false,false)
	check(c.bullets.is_empty() and c.cancel_effects.size()==1,"tunnelling bullet removed in actual update")
	check(c.cancel_effects[0].pos.x>695 and c.cancel_effects[0].pos.x<710,"remnant is born at entry, not end of swept segment")
	# Two overlapping waves choose the earliest physical contact, irrespective of storage order.
	c=fresh(); c._start_damage_wave(Vector2(700,400)); c._start_damage_wave(Vector2(660,400))
	var contact: Dictionary=c._damage_wave_contact({"radius":5},Vector2(600,400),Vector2(800,400))
	check(contact.origin==Vector2(660,400),"overlap resolves earliest front rather than oldest array entry")
	near(contact.time,.205,"overlap entry time")
	# New shots behind an already swept front survive, but shots ahead are still cleared.
	c=fresh(); c._hit_player(); origin=c.damage_waves[0].pos
	tick(c,.2)
	tagged(c,origin+Vector2(30,0),Vector2.ZERO,10)
	tagged(c,origin+Vector2(500,0),Vector2.ZERO,11)
	check(c.bullets[0].get("passed_waves",{}).size()==1 and not c.bullets[1].has("passed_waves"),"only behind-front births receive a wave-specific exemption")
	tick(c,.4)
	check(count_id(c,10)==1 and count_id(c,11)==0,"wave is not a lingering filled-disc absorber")
	c.invulnerable=0; c.player=origin+Vector2(30,0); c._hit_player(); tick(c,.02)
	check(count_id(c,10)==0,"an old exemption does not exempt a later hit wave")
	# Damage immunity is temporal only; new bullets become dangerous again after it ends.
	c=fresh(); c._hit_player(); tick(c,3.1)
	tagged(c,c.player,Vector2.ZERO,12); c.step(1.0/120,Vector2.ZERO,false,false,false)
	check(c.lives==1,"normal damage resumes after three-second protection")
	# No wave/remnant state or pool growth can leak through restart, repeated reuse, or resize.
	c=fresh()
	for repeat in 4:
		for i in 900: c._cancel_bullet({"radius":5,"color":Core.PINK},Vector2(i,500),Vector2.ZERO,0)
		check(c.cancel_effects.size()==Core.MAX_CANCEL_EFFECTS,"dense remnant cap pass "+str(repeat))
		c._update_cancel_effects(.3)
		check(c._cancel_pool.size()==Core.MAX_CANCEL_EFFECTS,"pool recycling does not grow pass "+str(repeat))
	c._start_damage_wave(Vector2(200,300)); c._update_damage_waves(.2)
	c.resize_field(Vector2(1920,1080))
	check(c.damage_waves[0].pos.is_equal_approx(Vector2(200,300)*Vector2(1920.0/1440,1080.0/960)),"resize maps fixed origin with gameplay canvas")
	near(c.damage_waves[0].radius,Core.damage_wave_radius(c.damage_waves[0]),"resize keeps render/contact extent coherent")
	c.start()
	check(c.damage_waves.is_empty() and c.cancel_effects.is_empty() and c._next_damage_wave_id==1 and c._cancel_pool.size()<=Core.MAX_CANCEL_EFFECTS,"restart cleans wave identities and active remnants")
	# Presentation remnants cannot damage or graze even when protection is disabled.
	c=fresh(); c._cancel_bullet({"radius":30,"color":Core.PINK},c.player,c.player,0)
	c.step(1.0/120,Vector2.ZERO,false,false,false)
	check(c.lives==3 and c.graze==0 and c.cancel_effects.size()==1,"visible remnant is strictly noncolliding")
	# Invalid/resume deltas preserve the existing capped simulation contract.
	c=fresh(); c._hit_player()
	var held: Array=c.damage_waves.duplicate(true)
	c.step(NAN,Vector2.ZERO,false,false,false); c.step(-1,Vector2.ZERO,false,false,false)
	check(c.damage_waves==held,"invalid deltas cannot advance wave")
	c.step(10,Vector2.ZERO,false,false,false)
	near(c.damage_waves[0].age,.1,"large resume delta remains capped")
	# Ordinary pulse scoring remains immediate and independent of damage waves.
	c=fresh(); tagged(c,Vector2(200,200),Vector2.ZERO,1); c._use_bomb()
	check(c.bullets.is_empty() and c.damage_waves.is_empty() and c.score==5 and c.bombs==2,"pulse behavior unchanged")
	# Same simulated time, different render deltas must agree exactly on cancellation.
	var a=fresh(); var b=fresh()
	for sim in [a,b]:
		for i in 60: tagged(sim,Vector2(100+i*20,100+i*9),Vector2(-30,40),i)
		sim._hit_player()
	tick(a,.3,Vector2.ZERO,1.0/30); tick(b,.3,Vector2.ZERO,1.0/120)
	check(a.bullets==b.bullets and a.cancel_effects==b.cancel_effects and a.damage_waves==b.damage_waves,"30/120Hz cancellation state deterministic")
	print("INDEPENDENT SHIELD: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
