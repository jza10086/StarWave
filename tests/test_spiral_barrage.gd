extends SceneTree
## Independent barrage regression. Fixture invulnerability isolates pattern geometry;
## ordinary-input difficulty observations remain separate in test_flow/test_patterns.
const Core = preload("res://scripts/game_core.gd")
const Pilot = preload("res://tests/test_patterns.gd")
const DT := 1.0 / 120.0
var checks := 0
var failures := 0

func _initialize(): call_deferred("run")

func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func fixture(phase: int, size := Vector2(1440,960)):
	var c = Core.new()
	c.resize_field(size)
	c.debug_set_boss(phase)
	c.invulnerable = 100.0
	return c

func nearest_tip(c, point: Vector2) -> float:
	var nearest := INF
	for blade in 6:
		nearest = minf(nearest, point.distance_to(c.boss_blade_position(blade)))
	return nearest

func ring_coverage():
	for size in [Vector2(1440,960),Vector2(1706.666667,960),Vector2(1440,1800)]:
		var c = fixture(3,size)
		c.boss.rotation = .77
		c.boss.bank = -.07
		for blade in 6: c.boss.blade_openings[blade] = .12 + blade * .15
		c._boss_radial_ring(36,0.0,220.0,Core.PURPLE,0.0)
		var angles: Array[float] = []
		var downward := 0
		var directly_down := false
		var error := 0.0
		for b in c.bullets:
			angles.append(wrapf(b.vel.angle(),0,TAU))
			if b.vel.y > .001: downward += 1
			if absf(wrapf(b.vel.angle()-PI*.5,-PI,PI)) < .001: directly_down = true
			error = maxf(error,nearest_tip(c,b.pos))
		angles.sort()
		var maximum_gap := 0.0
		for i in angles.size():
			maximum_gap = maxf(maximum_gap,wrapf(angles[(i+1)%angles.size()]-angles[i],0,TAU))
		check(c.bullets.size()==36,"all 36 radial directions retained / "+str(size))
		check(downward==17 and directly_down,"lower semicircle includes exact downward bullet / "+str(size))
		check(maximum_gap <= TAU/36.0+.0001,"360-degree ring has no deleted fairness wedge / "+str(size))
		check(error < .001,"radial births use actual banked articulated tips / "+str(size))
		var lower_occupancy := 0
		var direct_down_reaches := false
		# Observe travel into the lower field, not merely the initial direction.
		for tick in int(ceil((size.y*.78-205.0)/220.0/DT)):
			c._update_bullets(DT)
			var lower := 0
			for b in c.bullets:
				if b.pos.y > size.y*.58 and b.pos.x >= 0 and b.pos.x <= size.x:
					lower += 1
					if absf(wrapf(b.vel.angle()-PI*.5,-PI,PI)) < .001: direct_down_reaches = true
			lower_occupancy = maxi(lower_occupancy,lower)
		check(lower_occupancy>=5 and direct_down_reaches,"downward ring persists into lower playfield / "+str(size))
		print("RADIAL_COVERAGE field=",size," directions=",angles.size()," downward=",downward," maximum_angular_gap=",maximum_gap," lower_occupancy=",lower_occupancy," tip_error=",error)
	var capped = fixture(3)
	for i in Core.MAX_BULLETS:
		capped._add_bullet(Vector2(100,100),Vector2.DOWN*170,6,Core.PURPLE)
	var old: Array = capped.bullets.duplicate(true)
	capped._boss_radial_ring(42,0,230,Core.PURPLE,.16)
	check(capped.bullets.size()==Core.MAX_BULLETS and capped.bullets==old,"capped radial emitter neither overflows nor mutates prior projectile")
	for i in 5: capped.bullets.pop_back()
	old=capped.bullets.duplicate(true)
	capped._boss_spiral_volley(3,0)
	check(capped.bullets==old,"spiral cap admission preserves complete six-arm volley instead of deleting last/lower tips")
	capped.bullets.clear()
	capped.player=capped.boss_blade_position(2)+Vector2(0,40)
	capped._boss_spiral_volley(3,0)
	capped._boss_radial_ring(42,0,230,Core.PURPLE,.16)
	check(capped.bullets.is_empty(),"point-blank guard defers whole radial/spiral pattern, never selected angular sectors")
	capped.player=Vector2(720,900)
	capped._boss_spiral_volley(3,0)
	check(capped.bullets.size()==6,"spiral emits every tip once clearance is restored")

func live_barrage(phase: int):
	var c = fixture(phase)
	var emitted := 0
	var spiral_births := 0
	var radial_births := 0
	var spiral_down := 0
	var spiral_tip_error := 0.0
	var peak := 0
	var peak_lower := 0
	var active_speed_sum := 0.0
	var active_frames := 0
	var minimum_spin := INF
	var full_volley_count := 0
	var largest_birth_batch := 0
	var lower_columns: Dictionary = {}
	var emission_angles: Dictionary = {}
	var phrases: Dictionary = {}
	var tracked: Dictionary = {}
	var tracked_origin := Vector2.ZERO
	var tracked_velocity := Vector2.ZERO
	var curve_checked := false
	var rest_births := 0
	var last_spiral_time := -1.0
	var breathing_breaks := 0
	var maximum_spiral_pause := 0.0
	for frame in 120*30:
		var before: int = c.bullets.size()
		var old_rotation: float = c.boss.rotation
		c._update_boss(DT)
		var batch: int = c.bullets.size()-before
		emitted += batch
		largest_birth_batch = maxi(largest_birth_batch,batch)
		var spiral_batch := 0
		var phrase: String = c.boss.get("phrase","")
		phrases[phrase] = true
		if phrase=="rest": rest_births += batch
		if phrase=="spiral":
			active_frames += 1
			active_speed_sum += float(c.boss.rotation_speed)
			minimum_spin = minf(minimum_spin,wrapf(float(c.boss.rotation)-old_rotation,-PI,PI))
		for i in range(before,c.bullets.size()):
			var b: Dictionary = c.bullets[i]
			if b.get("pattern","")=="radial": radial_births += 1
			if b.get("pattern","")!="spiral": continue
			spiral_births += 1
			spiral_batch += 1
			spiral_tip_error = maxf(spiral_tip_error,nearest_tip(c,b.pos))
			if b.vel.y > 0: spiral_down += 1
			emission_angles[int(floor(wrapf(b.vel.angle(),0,TAU)/(TAU/24.0)))] = true
			if tracked.is_empty() and b.vel.y > Vector2(b.vel).length()*.95:
				tracked=b
				tracked_origin=b.pos
				tracked_velocity=b.vel
		if spiral_batch>=6:
			full_volley_count += 1
			var now:=frame*DT
			if last_spiral_time>=0 and now-last_spiral_time<1.0:
				maximum_spiral_pause=maxf(maximum_spiral_pause,now-last_spiral_time)
				if now-last_spiral_time>=.199: breathing_breaks+=1
			last_spiral_time=now
		c._update_bullets(DT)
		peak=maxi(peak,c.bullets.size())
		var lower := 0
		for b in c.bullets:
			if b.get("pattern","")=="spiral" and b.pos.y>c.field_size.y*.5 and b.pos.x>=0 and b.pos.x<c.field_size.x:
				lower += 1
				lower_columns[int(b.pos.x/(c.field_size.x/12.0))]=true
		peak_lower=maxi(peak_lower,lower)
		if not curve_checked and not tracked.is_empty() and float(tracked.age)>=2.0:
			var age: float = tracked.age
			var curve: float = tracked.angular_velocity
			var curved_time: float = minf(age,tracked.curve_duration)
			var turned := tracked_velocity.rotated(curve*curved_time)
			var expected := tracked_origin+Vector2(turned.y-tracked_velocity.y,tracked_velocity.x-turned.x)/curve+turned*(age-curved_time)
			check(curve>0 and absf(wrapf(tracked.vel.angle()-tracked_velocity.angle(),-PI,PI))>.2,"spiral has real clockwise projectile turn / phase "+str(phase))
			check(tracked.pos.distance_to(tracked_origin+tracked_velocity*age)>30,"spiral flight is not a straight shot with decorative wake / phase "+str(phase))
			check(tracked.pos.distance_to(expected)<.02,"spiral real path agrees with exact arc/tangent model / phase "+str(phase))
			curve_checked=true
	check(phrases.has("spiral") and phrases.has("rest"),"distinct spiral and recovery phrases / phase "+str(phase))
	check(spiral_births>=800 and full_volley_count>=130,"substantial repeated six-arm spiral / phase "+str(phase))
	check(breathing_breaks>=6 and maximum_spiral_pause>=.20,"repeatable temporal breathing corridors between spiral pulses / phase "+str(phase))
	check(radial_births>=180,"repeated full radial waves / phase "+str(phase))
	check(spiral_down>=spiral_births*.40 and spiral_down<=spiral_births*.60,"spiral does not discard lower emission sector / phase "+str(phase))
	check(emission_angles.size()==24,"spiral covers every 15-degree sector / phase "+str(phase))
	check(peak_lower>=15 and lower_columns.size()>=9,"spiral fills broad lower field rather than only Boss vicinity / phase "+str(phase))
	check(spiral_tip_error<.001,"every spiral birth matches a real animated tip / phase "+str(phase))
	check(active_frames>0 and active_speed_sum/maxi(1,active_frames)>5.5 and minimum_spin>0,"rapid eased clockwise spin accompanies spiral / phase "+str(phase))
	check(curve_checked,"downfield spiral projectile retained for real-path observation / phase "+str(phase))
	check(rest_births==0,"recovery remains free of fresh emissions / phase "+str(phase))
	check(peak<Core.MAX_BULLETS and largest_birth_batch<=48,"dense barrage stays bounded without relying on cap truncation / phase "+str(phase))
	print("SPIRAL_LIVE phase=",phase," emitted=",emitted," radial=",radial_births," spiral=",spiral_births," downward=",spiral_down," full_volleys=",full_volley_count," breathing_breaks=",breathing_breaks," angular_bins=",emission_angles.size()," lower_columns=",lower_columns.size()," lower_peak=",peak_lower," peak=",peak," batch=",largest_birth_batch," tip_error=",spiral_tip_error," active_mean_speed=",active_speed_sum/maxi(1,active_frames))

func frame_invariance():
	var models: Array = []
	for hz in [30,60,120]:
		var c=fixture(3)
		for frame in hz*28: c.step(1.0/hz,Vector2.ZERO,false,false,false)
		models.append(c)
	var reference=models.back()
	for i in 2:
		var c=models[i]
		var match_paths: bool = c.bullets.size()==reference.bullets.size()
		var maximum_error := 0.0
		for b in mini(c.bullets.size(),reference.bullets.size()):
			maximum_error=maxf(maximum_error,c.bullets[b].pos.distance_to(reference.bullets[b].pos))
			if maximum_error>.002 or c.bullets[b].get("pattern","")!=reference.bullets[b].get("pattern",""): match_paths=false
		check(match_paths,"28-second barrage count and paths match 120 Hz / "+str([30,60][i])+" Hz")
		check(absf(wrapf(c.boss.rotation-reference.boss.rotation,-PI,PI))<.0001 and c.boss.pos.distance_to(reference.boss.pos)<.001,"rapid rotor and Boss path are frame-rate independent / "+str([30,60][i])+" Hz")
		print("SPIRAL_TIMESTEP hz=",[30,60][i]," count=",c.bullets.size()," maximum_path_error=",maximum_error)

## A time-connected focus-speed route, not merely disconnected safe screen cells.
## Targeting is held at center in this deterministic fixture; this is NOT a claim
## that every input/position is safe or a replacement for the normal-input pilot.
func connected_corridor(size: Vector2,label: String):
	var c=fixture(3,size)
	var row: float=size.y-180.0
	c.player=Vector2(size.x*.5,row)
	const SPACING := 16.0
	const TICKS := 15
	const INTERVAL := DT*TICKS
	var count:=int(floor((size.x-96)/SPACING))+1
	var reachable:=PackedByteArray()
	reachable.resize(count)
	reachable.fill(0)
	reachable[int(round((size.x*.5-48)/SPACING))]=1
	var minimum_reachable:=count
	var first_sealed:=-1.0
	var peak_near_row:=0
	var lower_passages:=0
	var tick_time:=0.0
	for interval in 240:
		# Retain dictionaries through cleanup so each path's exact old/new positions
		# are available. Births are above this row and cannot create hidden gaps here.
		var motions: Array=[]
		for b in c.bullets: motions.append([b,Vector2(b.pos)])
		for tick in TICKS:
			var before: int=c.bullets.size()
			c._update_boss(DT)
			for i in range(before,c.bullets.size()): motions.append([c.bullets[i],Vector2(c.bullets[i].pos)])
			c._update_bullets(DT)
			tick_time+=DT
		var nearby: Array=[]
		for motion in motions:
			var from: Vector2=motion[1]
			var to: Vector2=motion[0].pos
			var radius: float=motion[0].radius+Core.PLAYER_RADIUS+2.0
			# +2px is extra clearance beyond both physical circular hitboxes;
			# it also exceeds the subpixel arc/chord sagitta over this 125ms slice.
			if minf(from.y,to.y)-radius<=row and maxf(from.y,to.y)+radius>=row:
				nearby.append([from,to,radius*radius])
		peak_near_row=maxi(peak_near_row,nearby.size())
		var next:=PackedByteArray()
		next.resize(count)
		next.fill(0)
		var open:=0
		for destination in count:
			var p1:=Vector2(48+destination*SPACING,row)
			for source in range(maxi(0,destination-1),mini(count,destination+2)):
				if reachable[source]==0: continue
				var p0:=Vector2(48+source*SPACING,row)
				var safe:=true
				for motion in nearby:
					if Core._segment_distance_squared(Vector2.ZERO,motion[0]-p0,motion[1]-p1)<motion[2]:
						safe=false
						break
				if safe:
					next[destination]=1
					open+=1
					break
		reachable=next
		if not nearby.is_empty():
			lower_passages+=1
			minimum_reachable=mini(minimum_reachable,open)
		if open==0:
			first_sealed=tick_time
			break
	check(SPACING/INTERVAL<Core.FOCUS_SPEED,"corridor planner respects focus movement speed / "+label)
	check(first_sealed<0 and minimum_reachable>0,"continuous collision-clear route from center through two dense phrases / "+label)
	check(lower_passages>20 and peak_near_row>0,"corridor test actually encounters downfield projectiles / "+label)
	print("SPIRAL_CORRIDOR label=",label," field=",size," row=",row," tested_seconds=",tick_time," first_sealed=",first_sealed," minimum_reachable=",minimum_reachable," peak_near_row=",peak_near_row," occupied_intervals=",lower_passages," route_speed=",SPACING/INTERVAL," padding=2")

## Separate closed-loop observation under normal collision rules. We initialize
## directly at phase 3, then use only ordinary movement, no firing or bombs. No
## health/pattern/clock edits or extended invulnerability occur during this run.
## One reactive controller is evidence of survivability, not human playtesting.
func normal_rule_survival(size: Vector2,label: String):
	var c=Core.new()
	c.resize_field(size)
	c.debug_set_boss(3)
	var direction:=Vector2.ZERO
	var peak:=0
	for frame in 60*30:
		if c.state!="playing": break
		if frame%6==0: direction=Pilot.steer(c)
		c.step(1.0/60,direction,false,false,false)
		peak=maxi(peak,c.bullets.size())
	check(c.state=="playing" and c.lives>0 and absf(c.elapsed-Core.BOSS_TIME-30)<.001,"normal-rule movement controller survives two complete phrases / "+label)
	check(c.bombs==3 and c.shots.is_empty(),"survival observation uses neither bombs nor outgoing fire / "+label)
	print("SPIRAL_PILOT label=",label," field=",size," state=",c.state," lives=",c.lives," bombs=",c.bombs," seconds=",c.elapsed-Core.BOSS_TIME," peak=",peak)

func run():
	ring_coverage()
	for phase in [1,2,3]: live_barrage(phase)
	frame_invariance()
	connected_corridor(Vector2(1706.666667,960),"landscape1920x1080")
	connected_corridor(Vector2(1440,1800),"portrait800x1000")
	connected_corridor(Vector2(1440,960),"small960x640")
	normal_rule_survival(Vector2(1706.666667,960),"landscape1920x1080")
	normal_rule_survival(Vector2(1440,1800),"portrait800x1000")
	normal_rule_survival(Vector2(1440,960),"small960x640")
	print("SPIRAL_BARRAGE_TESTS ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
