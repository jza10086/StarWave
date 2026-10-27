extends SceneTree
## Actual Compatibility renderer / deterministic gameplay, not composited artwork.
const Core = preload("res://scripts/game_core.gd")
const Pilot = preload("res://tests/test_patterns.gd")
var app
var output: String
var checks := 0
var failed := 0
var peak_bullets := 0
var render_samples: Array[float] = []
var pilot_tick := 0
var pilot_direction := Vector2.ZERO
func _initialize(): call_deferred("run")
func check(ok: bool,label: String):
	checks += 1
	if not ok: failed += 1; push_error(label)
func key(code: int):
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	app._unhandled_input(event)
func snap(label: String):
	app.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label+".png"))==OK,label)
func advance(ticks: int):
	for i in ticks:
		if pilot_tick % 6 == 0: pilot_direction = Pilot.steer(app.core)
		pilot_tick += 1
		app.core.step(1.0/120,pilot_direction,false,false,false)
		app.visual_time += 1.0/120
		peak_bullets = maxi(peak_bullets,app.core.bullets.size())
func run():
	output = OS.get_environment("CAPTURE_DIR")
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1440,960)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.muted = true
	app.set_process(false)
	await process_frame
	app._start()
	app.core.debug_set_boss(3)
	advance(120*10)
	await snap("01-downfield-spiral")
	# Exercise the previously degenerate final instant of a player-hit fragment.
	app.core._add_effect(app.core.player,"hurt",55.0,.9)
	app.core.effects.back()["age"] = .9-.00000001
	await snap("effect-lifetime-epsilon")
	app.core.effects.clear()
	if OS.get_environment("QUICK_CAPTURE")=="1":
		print("SPIRAL_QUICK checks=",checks," failed=",failed," bullets=",app.core.bullets.size()," lives=",app.core.lives)
		quit(1 if failed else 0)
		return
	root.size = Vector2i(1920,1080)
	await process_frame
	app.core.debug_set_boss(2)
	advance(120*10)
	await snap("02-landscape")
	var held: Dictionary = app.core.boss.duplicate(true)
	key(KEY_P)
	app._process(.04)
	check(app.paused and app.core.boss==held,"pause freezes spiral and articulated blades")
	await snap("03-pause")
	key(KEY_ENTER)
	app._process(.04)
	check(not app.paused and app.core.boss.rotation != held.rotation,"resume advances spiral")
	key(KEY_P)
	key(KEY_R)
	check(app.core.boss.is_empty() and app.core.elapsed==0 and not app.paused,"restart clears spiral ticks")
	root.size = Vector2i(800,1000)
	await process_frame
	app.core.debug_set_boss(3)
	advance(120*14)
	await snap("04-portrait-downfield")
	root.size = Vector2i(960,640)
	await process_frame
	app.core.debug_set_boss(3)
	var frames := output.path_join("spiral-motion")
	DirAccess.make_dir_recursive_absolute(frames)
	var moving_frames := 0
	var maximum_rotor_step := 0.0
	var seen_spiral := 0
	# 27.9 continuous seconds, no HP/timer/collision edits, normal movement input;
	# firing held off so the Boss lives through two complete spiral casts.
	var verify_existing := OS.get_environment("VERIFY_CAPTURE")=="1"
	for frame in 558:
		var before: float = app.core.boss.rotation
		advance(6)
		var rotor_step := absf(wrapf(app.core.boss.rotation-before,-PI,PI))
		maximum_rotor_step = maxf(maximum_rotor_step,rotor_step)
		if rotor_step>.001: moving_frames += 1
		if app.core.boss.get("phrase","")=="spiral": seen_spiral += 1
		if verify_existing and frame not in [0,118,162,200,240,454,492,557]: continue
		var started := Time.get_ticks_usec()
		app.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		render_samples.append((Time.get_ticks_usec()-started)/1000.0)
		var frame_path := frames.path_join("frame-%04d.png"%frame)
		if verify_existing:
			var prior := Image.load_from_file(frame_path)
			var rendered := root.get_texture().get_image()
			check(prior.get_data()==rendered.get_data(),"native replay matches saved frame "+str(frame))
		else:
			check(root.get_texture().get_image().save_png(frame_path)==OK,"motion frame")
		if frame in [118,162,200,240,454,492]: await snap("motion-%03d"%frame)
	check(app.core.state=="playing","normal movement-only controller survives 27.9-second gameplay clip")
	check(moving_frames==558,"every frame has true simulated clockwise rotation")
	check(seen_spiral>150,"two visible spiral skills recorded")
	check(maximum_rotor_step<PI/6.0,"20fps avoids six-blade rotational aliasing at peak speed")
	check(app.shape_cache.size()<128,"fixed geometry cache remains bounded")
	render_samples.sort()
	print("SPIRAL_CAPTURE ",checks," checks, ",failed," failures; 558 frames / 20fps =27.9s; moving=",moving_frames," spiral_frames=",seen_spiral," peak=",peak_bullets," lives=",app.core.lives," cache=",app.shape_cache.size()," llvmpipe_render_median_ms=",render_samples[render_samples.size()/2]," p95_ms=",render_samples[int(render_samples.size()*.95)])
	app.queue_free()
	await process_frame
	quit(1 if failed else 0)
