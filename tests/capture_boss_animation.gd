extends SceneTree
## Native Compatibility render; real 120Hz simulation, no hand-animated mock-up.
const Core = preload("res://scripts/game_core.gd")
const Pilot = preload("res://tests/test_patterns.gd")
var app
var output: String
var checks := 0
var failed := 0
var peak_bullets := 0
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
		app.core.step(1.0/120,Pilot.steer(app.core),false,false,false)
		app.visual_time += 1.0/120
		peak_bullets=maxi(peak_bullets,app.core.bullets.size())
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
	app.core.debug_set_boss(2)
	advance(400)
	await snap("01-boss-open")
	advance(400)
	await snap("02-boss-closed")
	if OS.get_environment("QUICK_CAPTURE")=="1":
		print("QUICK_CAPTURE ",checks," failed=",failed)
		quit(1 if failed else 0)
		return
	root.size = Vector2i(1920,1080)
	await process_frame
	app.core.debug_set_boss(3)
	advance(575)
	await snap("03-boss-landscape")
	var held: Dictionary = app.core.boss.duplicate(true)
	key(KEY_P)
	app._process(.04)
	check(app.paused and app.core.boss==held,"pause freezes all articulated simulation")
	await snap("04-paused")
	key(KEY_ENTER)
	app._process(.04)
	check(not app.paused and app.core.boss.rotation != held.rotation,"resume advances blades")
	key(KEY_P)
	key(KEY_R)
	check(app.core.boss.is_empty() and app.core.elapsed==0 and not app.paused,"restart resets choreography")
	root.size = Vector2i(800,1000)
	await process_frame
	app.core.debug_set_boss(3)
	advance(575)
	await snap("05-boss-portrait")
	root.size = Vector2i(960,640)
	await process_frame
	var frames := output.path_join("boss-motion")
	DirAccess.make_dir_recursive_absolute(frames)
	var moving_frames := 0
	var all_phrases: Dictionary = {}
	# Each segment is exactly 18 seconds: 1.2s intro + two full 8.4s phrases.
	for phase in [1,2,3]:
		app._start()
		app.core.debug_set_boss(phase)
		for frame in 216:
			var before: float = app.core.boss.rotation
			advance(10)
			if absf(wrapf(app.core.boss.rotation-before,-PI,PI))>.001: moving_frames += 1
			all_phrases[str(phase)+"/"+app.core.boss.get("phrase","")] = true
			app.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(frames.path_join("frame-%04d.png"%((phase-1)*216+frame)))==OK,"motion frame")
			if phase==2 and frame in [18,34,47,67,91,113,138,169]:
				await snap("pose-%03d"%frame)
		check(app.core.state=="playing","normal movement-only controller survives two phrases phase "+str(phase))
		for phrase in ["reposition","blades","curves","expand","rest"]:
			check(all_phrases.has(str(phase)+"/"+phrase),"recorded phrase "+str(phase)+"/"+phrase)
	check(moving_frames==648,"all captured frames have simulated clockwise motion")
	check(app.shape_cache.size()<128,"bounded fixed-shape texture cache")
	print("BOSS_ANIMATION_CAPTURE ",checks," checks, ",failed," failures; 648 frames / 12 fps = 54s; moving=",moving_frames," peak_bullets=",peak_bullets," lives=",app.core.lives," cache=",app.shape_cache.size())
	app.queue_free()
	await process_frame
	quit(1 if failed else 0)
