extends SceneTree
## Real Compatibility renderer and normal collision/movement after encounter setup.
const Core = preload("res://scripts/game_core.gd")
const Pilot = preload("res://tests/test_patterns.gd")
var app
var output: String
var checks := 0
var failures := 0
var pilot_tick := 0
var direction := Vector2.ZERO
var peak_bullets := 0
var peak_remnants := 0
var hit_count := 0
var render_samples: Array[float] = []
func _initialize(): call_deferred("run")
func check(ok: bool,label: String):
	checks += 1
	if not ok: failures += 1; push_error(label)
func key(code: int):
	var event := InputEventKey.new()
	event.keycode=code; event.pressed=true
	app._unhandled_input(event)
func advance(ticks: int):
	for i in ticks:
		if pilot_tick%6==0: direction=Pilot.steer(app.core)
		pilot_tick += 1
		var lives: int = app.core.lives
		app.core.step(1.0/120,direction,false,false,false)
		app.visual_time += 1.0/120
		peak_bullets=maxi(peak_bullets,app.core.bullets.size())
		peak_remnants=maxi(peak_remnants,app.core.cancel_effects.size())
		if app.core.lives<lives:
			hit_count += 1
			print("ACTUAL_HIT t=",pilot_tick/120.0," origin=",app.core.damage_waves.back().pos," still_dangerous=",app.core.bullets.size()," lives=",app.core.lives)
func snap(path: String):
	var start := Time.get_ticks_usec()
	app.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	render_samples.append((Time.get_ticks_usec()-start)/1000.0)
	check(root.get_texture().get_image().save_png(path)==OK,"native frame saved")
func run():
	output=OS.get_environment("CAPTURE_DIR")
	DirAccess.make_dir_recursive_absolute(output.path_join("motion"))
	root.size=Vector2i(660,440)
	app=load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.muted=true; app.set_process(false)
	await process_frame
	app._start(); app.core.debug_set_boss(3)
	advance(360)
	var wave_frames := 0
	var mixed_frames := 0
	var last_radius := 0.0
	for frame in 360:
		advance(6)
		if not app.core.damage_waves.is_empty():
			wave_frames += 1
			var shield: Dictionary=app.core.damage_waves[0]
			check(is_equal_approx(shield.radius,Core.damage_wave_radius(shield)),"render and collision share wave radius")
			check(shield.radius>=last_radius,"front advances monotonically")
			last_radius=shield.radius
			if not app.core.cancel_effects.is_empty() and app.core.bullets.size()>20: mixed_frames += 1
			for bullet in app.core.bullets:
				if not bullet.get("passed_waves",{}).has(shield.id):
					check(Vector2(bullet.pos).distance_to(shield.pos)>shield.radius+bullet.radius-.05,"no dangerous bullet remains inside swept front")
			print("WAVE frame=",frame," age=",shield.age," radius=",shield.radius," hazards=",app.core.bullets.size()," dissolves=",app.core.cancel_effects.size())
		await snap(output.path_join("motion/frame-%04d.png"%frame))
		if frame in [140,144,146,148,150,153]:
			check(root.get_texture().get_image().save_png(output.path_join("wave-%03d.png"%frame))==OK,"contact still")
	check(app.core.state=="playing" and app.core.lives==2,"controller survives actual 18 second clip with one real hit")
	check(hit_count==1 and wave_frames>=10 and mixed_frames>=5,"real hit visibly clears in stages, not instantly")
	check(peak_bullets>250 and peak_remnants>50,"dense spiral and individual cancellation are both present")
	check(peak_remnants<=Core.MAX_CANCEL_EFFECTS,"presentation pool stays bounded")
	# Independent native pause/resume/restart on a controlled shield state.
	app.core.invulnerable=0.0; app.core._hit_player()
	var held=app.core.damage_waves.duplicate(true)
	key(KEY_P); app._process(.05)
	check(app.paused and app.core.damage_waves==held,"pause freezes shared wave and collision")
	await snap(output.path_join("pause.png"))
	key(KEY_ENTER); app._process(.05)
	check(not app.paused and app.core.damage_waves[0].radius>held[0].radius,"resume advances shared wave")
	key(KEY_P); key(KEY_R)
	check(app.core.damage_waves.is_empty() and app.core.cancel_effects.is_empty() and not app.paused,"restart removes all wave and cancellation state")
	# High-resolution actual replay stills; no hand-composited gameplay art.
	root.size=Vector2i(1440,960)
	await process_frame
	app.core.debug_set_boss(3); pilot_tick=0; direction=Vector2.ZERO
	advance(1200)
	for i in 8:
		advance(6)
		await snap(output.path_join("detail-%02d.png"%i))
	# Rendering lifetime epsilon remains safe for very small cancellation cores.
	for remnant in app.core.cancel_effects: remnant.age=Core.CANCEL_EFFECT_DURATION-0.00000001
	await snap(output.path_join("epsilon.png"))
	render_samples.sort()
	print("SHIELD_CAPTURE ",checks," checks, ",failures," failures; 360 native frames /20fps =18s; actual_hits=1; wave_frames=",wave_frames," mixed_frames=",mixed_frames," peak_bullets=",peak_bullets," peak_remnants=",peak_remnants," renderer_median_ms=",render_samples[render_samples.size()/2]," p95_ms=",render_samples[int(render_samples.size()*.95)])
	app.queue_free(); await process_frame
	quit(1 if failures else 0)
