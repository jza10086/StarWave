extends SceneTree
## Articulation fixtures test geometry/kinematics, not player difficulty.
const Core = preload("res://scripts/game_core.gd")
var checks := 0
var failures := 0
const DT := 1.0 / 120.0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func local_tip(c, blade: int) -> Vector2:
	return c.boss_blade_position(blade)-Vector2(c.boss.pos)
func nearest_tip_distance(c, position: Vector2) -> float:
	var nearest := INF
	for blade in 6: nearest = minf(nearest,position.distance_to(c.boss_blade_position(blade)))
	return nearest
func phase_motion(phase: int):
	var c = Core.new()
	c.debug_set_boss(phase)
	# Out-of-playfield target isolates clock/geometry; ordinary-play regressions are separate.
	c.player = Vector2(720,10000)
	var minimum_rotor := INF
	var minimum_tip := INF
	var minimum_iris := INF
	var minimum_hub := INF
	var maximum_speed := 0.0
	var minimum_speed := INF
	var maximum_acceleration := 0.0
	var maximum_stagger := 0.0
	var maximum_lag := 0.0
	var minimum_radius := INF
	var maximum_radius := 0.0
	var minimum_opening := INF
	var maximum_opening := 0.0
	var maximum_tip_step := 0.0
	var bank_range := 0.0
	var emission_error := 0.0
	var emitted := 0
	var rest_births := 0
	var peak := 0
	var max_batch := 0
	var rotor_total := 0.0
	var iris_total := 0.0
	var hub_total := 0.0
	var worst_tip_time := 0.0
	for frame in 3600:
		var old_rotation: float = c.boss.rotation
		var old_iris: float = c.boss.iris_rotation
		var old_hub: float = c.boss.hub_rotation
		var old_speed: float = c.boss.rotation_speed
		var old_tips: Array[Vector2] = []
		for blade in 6: old_tips.append(local_tip(c,blade))
		var before: int = c.bullets.size()
		c._update_boss(DT)
		var rotation_step := wrapf(float(c.boss.rotation)-old_rotation,-PI,PI)
		var iris_step := wrapf(float(c.boss.iris_rotation)-old_iris,-PI,PI)
		var hub_step := wrapf(float(c.boss.hub_rotation)-old_hub,-PI,PI)
		rotor_total += rotation_step
		iris_total += iris_step
		hub_total += hub_step
		minimum_rotor = minf(minimum_rotor,rotation_step)
		minimum_iris = minf(minimum_iris,iris_step)
		minimum_hub = minf(minimum_hub,hub_step)
		maximum_speed = maxf(maximum_speed,c.boss.rotation_speed)
		minimum_speed = minf(minimum_speed,c.boss.rotation_speed)
		maximum_acceleration = maxf(maximum_acceleration,absf(float(c.boss.rotation_speed)-old_speed)/DT)
		maximum_stagger = maxf(maximum_stagger,absf(float(c.boss.blade_openings[0])-float(c.boss.blade_openings[2])))
		maximum_lag = maxf(maximum_lag,absf(float(c.boss.blade_openings[0])-float(c.boss.iris_opening)))
		bank_range = maxf(bank_range,absf(float(c.boss.bank)))
		for blade in 6:
			var tip := local_tip(c,blade)
			var tip_step := wrapf(tip.angle()-old_tips[blade].angle(),-PI,PI)
			if tip_step < minimum_tip:
				minimum_tip = tip_step
				worst_tip_time = frame*DT
			maximum_tip_step = maxf(maximum_tip_step,tip.distance_to(old_tips[blade]))
			minimum_radius = minf(minimum_radius,tip.length())
			maximum_radius = maxf(maximum_radius,tip.length())
			minimum_opening = minf(minimum_opening,c.boss.blade_openings[blade])
			maximum_opening = maxf(maximum_opening,c.boss.blade_openings[blade])
		var batch: int = c.bullets.size()-before
		max_batch = maxi(max_batch,batch)
		emitted += batch
		if c.boss.phrase=="rest": rest_births += batch
		for i in range(before,c.bullets.size()):
			emission_error = maxf(emission_error,nearest_tip_distance(c,c.bullets[i].pos))
		peak = maxi(peak,c.bullets.size())
		c._update_bullets(DT)
	print("BOSS_ANIMATION phase=",phase," min_rotor_step=",minimum_rotor," min_tip_step=",minimum_tip," worst_tip_time=",worst_tip_time," min_iris_step=",minimum_iris," min_hub_step=",minimum_hub," speed_range=",Vector2(minimum_speed,maximum_speed)," max_acceleration=",maximum_acceleration," opening_range=",Vector2(minimum_opening,maximum_opening)," radius_range=",Vector2(minimum_radius,maximum_radius)," max_tip_step=",maximum_tip_step," stagger=",maximum_stagger," iris_lag=",maximum_lag," bank_max=",bank_range," emission_error=",emission_error," emitted=",emitted," max_batch=",max_batch," peak=",peak)
	check(minimum_rotor>0,"rotor clockwise throughout complete score / phase "+str(phase))
	check(minimum_tip>0,"all articulated tips clockwise incl hinge and bank / phase "+str(phase))
	check(minimum_iris>0 and minimum_hub>0,"secondary rotors also clockwise / phase "+str(phase))
	check(rotor_total-iris_total>5 and iris_total-hub_total>4,"distinct layer gearing / phase "+str(phase))
	check(maximum_speed>minimum_speed*8,"strong attack/rest speed contrast / phase "+str(phase))
	check(maximum_acceleration<16,"bounded eased acceleration / phase "+str(phase))
	check(maximum_opening-minimum_opening>.8 and maximum_radius-minimum_radius>22,"visible radial/hinge articulation / phase "+str(phase))
	check(maximum_stagger>.2 and maximum_lag>.3,"opposite-pair stagger and iris response lag / phase "+str(phase))
	check(maximum_tip_step<9,"continuous blade-tip path across cycle wrap / phase "+str(phase))
	check(emitted>50 and emission_error<.001,"all live births exactly at current articulated tips / phase "+str(phase))
	check(rest_births==0,"no fresh emissions in rest / phase "+str(phase))
	check(max_batch<=42 and peak<500,"intentional full rings and six-tip pulses remain bounded / phase "+str(phase))
	check(bank_range>.05 and bank_range<=.121,"bounded visible movement banking / phase "+str(phase))
func transform_contract():
	var c = Core.new()
	c.debug_set_boss(2)
	c.player=Vector2(720,10000)
	c.boss.rotation=1.23
	c.boss.bank=-.11
	for opening in [.04,.45,1.0]:
		for blade in 6:
			c.boss.blade_openings[blade]=opening
			var pose := Core.blade_transform(blade,c.boss.rotation,opening,c.boss.bank)
			var expected: Vector2 = c.boss.pos+pose*Core.BOSS_BLADE_TIP
			c.bullets.clear()
			c._boss_fan(blade,PI*.5,1,.1,170,Core.PURPLE,6,"orb",.20)
			check(c.bullets.size()==1 and c.bullets[0].pos.distance_to(expected)<.001,"bank+hinge+radius emission / blade %d opening %.2f"%[blade,opening])
	var source := FileAccess.get_file_as_string("res://scripts/main.gd")
	check(Core.boss_blade_polygon().has(Core.BOSS_BLADE_TIP),"rendered blade profile contains exact emitting tip")
	check(source.contains("Core.blade_transform(n,") and source.contains("world+pose.origin,pose.get_rotation()") and source.contains("_soft_polygon(Core.boss_blade_polygon(),col)"),"renderer consumes same transform/profile as emission")
func timestep_and_interruptions():
	var models: Array = []
	for rate in [30,60,120]:
		var c = Core.new()
		c.debug_set_boss(3)
		# Fixture invulnerability allows the identical stationary input to exercise 20s.
		c.invulnerable=100
		for frame in rate*30: c.step(1.0/rate,Vector2.ZERO,false,false,false)
		models.append(c)
	var reference = models.back()
	for model in models:
		check(absf(wrapf(float(model.boss.rotation)-float(reference.boss.rotation),-PI,PI))<.0001,"30s rotor rate invariance")
		check(model.boss.pos.distance_to(reference.boss.pos)<.001,"30s movement rate invariance")
		var tips_match := true
		for blade in 6:
			if model.boss_blade_position(blade).distance_to(reference.boss_blade_position(blade))>.001: tips_match=false
		check(tips_match,"30s articulated pose rate invariance")
		var bullets_match: bool = model.bullets.size()==reference.bullets.size()
		for i in mini(model.bullets.size(),reference.bullets.size()):
			if model.bullets[i].pos.distance_to(reference.bullets[i].pos)>.002: bullets_match=false
		check(bullets_match,"30s emitted trajectory rate invariance")
	var saved: Dictionary = reference.boss.duplicate(true)
	reference.state="ready"
	reference.step(.1,Vector2.ONE,true,true,true)
	check(reference.boss==saved,"inactive state freezes all layers and hinges")
	reference.start()
	check(reference.boss.is_empty(),"restart removes complete animation state")
	reference._spawn_boss()
	check(reference.boss.rotation==0 and reference.boss.iris_rotation==0 and reference.boss.hub_rotation==0,"new boss resets layer rotations")
	# Interrupt at every tenth of a second, including rapid opening and peak spin.
	var minimum_tip := INF
	var maximum_step := 0.0
	var maximum_speed_step := 0.0
	var worst_at := 0.0
	for transition in [Vector2(1,1500),Vector2(2,700)]:
		for sample in 145:
			var c = Core.new()
			c.debug_set_boss(int(transition.x))
			c.player=Vector2(720,10000)
			for frame in int((1.2+sample*.1)*120):
				c._update_boss(DT)
				c.bullets.clear()
			c.boss.hp=transition.y
			for frame in 240:
				var old: Array[Vector2]=[]
				for blade in 6: old.append(local_tip(c,blade))
				var speed: float=c.boss.rotation_speed
				c._update_boss(DT)
				c.bullets.clear()
				maximum_speed_step=maxf(maximum_speed_step,absf(float(c.boss.rotation_speed)-speed))
				for blade in 6:
					var tip:=local_tip(c,blade)
					var delta:=wrapf(tip.angle()-old[blade].angle(),-PI,PI)
					if delta<minimum_tip:
						minimum_tip=delta
						worst_at=sample*.1
					maximum_step=maxf(maximum_step,tip.distance_to(old[blade]))
	print("BOSS_INTERRUPTION min_tip_step=",minimum_tip," worst_interrupt_cycle=",worst_at," max_tip_step=",maximum_step," max_speed_step=",maximum_speed_step)
	check(minimum_tip>0,"all blades remain clockwise through phase interruptions at 145 score positions in both transitions")
	check(maximum_step<12 and maximum_speed_step<.14,"bounded pose/speed changes through all sampled interruptions")
func run():
	transform_contract()
	for phase in [1,2,3]: phase_motion(phase)
	timestep_and_interruptions()
	print("BOSS_ANIMATION_TESTS ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
