extends SceneTree
## Independent boundary fixtures: no scene/art assumptions and no production input edits.
const Core = preload("res://scripts/game_core.gd")
const Pilot = preload("res://tests/test_patterns.gd")
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
	near(Core.DAMAGE_WAVE_DURATION,1.5,"requested shield expansion duration")
	near(Core.CANCEL_EFFECT_DURATION,.5,"requested individual dissolve duration")
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
	tick(c,.5,Vector2.RIGHT)
	check(count_id(c,0)==0 and count_id(c,1)==0 and count_id(c,2)==1 and count_id(c,3)==1,"front clears only reached distances")
	check(c.damage_waves[0].pos==origin,"player motion does not tow wave")
	near(c.damage_waves[0].radius,Core.damage_wave_radius(c.damage_waves[0]),"shared visual and collision radius")
	tick(c,.25)
	check(count_id(c,2)==0 and count_id(c,3)==1,"middle distance cleared later than near distance")
	tick(c,Core.DAMAGE_WAVE_DURATION-.75+2.0/120)
	check(c.bullets.is_empty() and c.damage_waves.is_empty(),"last swept interval reaches retained offscreen bullet and expires")
	tick(c,Core.CANCEL_EFFECT_DURATION+1.0/120)
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
	tick(c,.5)
	tagged(c,origin+Vector2(30,0),Vector2.ZERO,10)
	tagged(c,origin+Vector2(500,0),Vector2.ZERO,11)
	check(c.bullets[0].get("passed_waves",{}).size()==1 and not c.bullets[1].has("passed_waves"),"only behind-front births receive a wave-specific exemption")
	tick(c,Core.DAMAGE_WAVE_DURATION-.5+2.0/120)
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
		c._update_cancel_effects(Core.CANCEL_EFFECT_DURATION)
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
	# Exact configured lifetimes: neither effect disappears at its former duration.
	c=fresh(); c._start_damage_wave(c.player)
	c._update_damage_waves(.58)
	check(c.damage_waves.size()==1 and c.damage_waves[0].radius<c.damage_waves[0].max_radius,"shield still expands after former .58-second duration")
	c._update_damage_waves(.91)
	check(c.damage_waves.size()==1 and c.damage_waves[0].radius<c.damage_waves[0].max_radius,"shield is not complete before 1.5 seconds")
	c._update_damage_waves(.01)
	near(c.damage_waves[0].age,1.5,"shield reaches final age at 1.5 seconds")
	near(c.damage_waves[0].radius,c.damage_waves[0].max_radius,"shield reaches full extent at 1.5 seconds")
	c._update_damage_waves(1.0/120)
	check(c.damage_waves.is_empty(),"final sweep retires on the following physics tick")
	c._cancel_bullet({"radius":5,"color":Core.PINK},c.player,c.player,0)
	c._update_cancel_effects(.20)
	check(c.cancel_effects.size()==1,"dissolve survives former .20-second duration")
	c._update_cancel_effects(.29)
	check(c.cancel_effects.size()==1,"individual dissolve remains active at .49 seconds")
	c._update_cancel_effects(.01)
	check(c.cancel_effects.is_empty(),"individual dissolve expires at .5 seconds")
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
	tick(a,.8,Vector2.ZERO,1.0/30); tick(b,.8,Vector2.ZERO,1.0/120)
	check(not a.cancel_effects.is_empty() and not a.bullets.is_empty(),"frame-rate fixture samples both reached and unreached bullets during slower sweep")
	check(a.bullets==b.bullets and a.cancel_effects==b.cancel_effects and a.damage_waves==b.damage_waves,"30/120Hz cancellation state deterministic")
	# Authored dense spiral, normal movement/collision, no life or immunity edits.
	# Track each live dictionary so pool reuse cannot silently shorten a .5s effect.
	c=Core.new(); c.debug_set_boss(3)
	var direction:=Vector2.ZERO
	var peak_remnants:=0
	var peak_bullets:=0
	var premature_reuses:=0
	var tracked_lifetimes:=0
	for frame in 21*120:
		if frame%6==0: direction=Pilot.steer(c)
		var retained: Array=[]
		for remnant in c.cancel_effects:
			if float(remnant.age)+1.0/120<Core.CANCEL_EFFECT_DURATION-.000001:
				retained.append([remnant,float(remnant.age),Vector2(remnant.pos)])
		c.step(1.0/120,direction,false,false,false)
		for prior in retained:
			tracked_lifetimes+=1
			if not c.cancel_effects.has(prior[0]) or absf(float(prior[0].age)-prior[1]-1.0/120)>.000001 or prior[0].pos!=prior[2]: premature_reuses+=1
		peak_remnants=maxi(peak_remnants,c.cancel_effects.size())
		peak_bullets=maxi(peak_bullets,c.bullets.size())
	check(c.state=="playing" and c.lives==2 and peak_bullets>250 and peak_remnants>50,"normal spiral density produces real hit and individual dissolves")
	check(tracked_lifetimes>0 and premature_reuses==0 and peak_remnants<Core.MAX_CANCEL_EFFECTS,"normal spiral keeps every dissolve alive for its full .5-second lifetime without saturating pool")
	print("SHIELD_NORMAL_DENSITY peak_bullets=",peak_bullets," peak_remnants=",peak_remnants," tracked_lifetime_intervals=",tracked_lifetimes," premature_reuses=",premature_reuses)
	print("INDEPENDENT SHIELD: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
