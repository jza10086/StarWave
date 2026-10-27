extends SceneTree
## Actual Compatibility renderer. Two clearly separate real-simulation scenes: routes, then Boss phrases.
const Pilot = preload("res://tests/test_patterns.gd")
var app
var output: String
var checks := 0
var failed := 0
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
func enemy_scene(warmup: int = 500):
	app._start()
	# Deliberately arranged role gallery; all motion / attacks still use real core rules.
	app.core._boss_spawned = true
	var types := ["sniper","sweeper","orbiter"]
	for i in 3: app.core._spawn_enemy(types[i],Vector2(app.FIELD.x*(.25+i*.25),-48-i*48),i)
	advance(warmup)
func run():
	output = OS.get_environment("CAPTURE_DIR")
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1440,960)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.muted = true
	app.set_process(false)
	await process_frame
	enemy_scene()
	await snap("01-new-enemies")
	root.size = Vector2i(800,1000)
	await process_frame
	enemy_scene()
	await snap("02-new-enemies-portrait")
	root.size = Vector2i(1920,1080)
	await process_frame
	app._start()
	app.core.debug_set_boss(2)
	advance(870)
	await snap("03-boss-landscape")
	var rotation: float = app.core.boss.rotation
	key(KEY_P)
	app._process(.04)
	check(app.paused and app.core.boss.rotation==rotation,"pause freezes blade simulation")
	await snap("04-paused")
	key(KEY_ENTER)
	app._process(.04)
	check(not app.paused and app.core.boss.rotation != rotation,"resume advances blades")
	key(KEY_P)
	key(KEY_R)
	check(app.core.boss.is_empty() and app.core.elapsed==0 and not app.paused,"restart resets choreography")
	root.size = Vector2i(800,1000)
	await process_frame
	app.core.debug_set_boss(3)
	advance(870)
	await snap("05-boss-portrait")
	root.size = Vector2i(960,640)
	await process_frame
	app.core.debug_set_boss(2)
	var frames := output.path_join("flow-motion")
	DirAccess.make_dir_recursive_absolute(frames)
	enemy_scene(0)
	var moving_frames := 0
	for frame in 240:
		if frame == 96:
			app._start()
			app.core.debug_set_boss(2)
		var before: Vector2 = app.core.enemies[0].pos if not app.core.enemies.is_empty() else app.core.boss.get("pos",Vector2.ZERO)
		advance(10)
		var after: Vector2 = app.core.enemies[0].pos if not app.core.enemies.is_empty() else app.core.boss.get("pos",Vector2.ZERO)
		if before.distance_to(after)>.01: moving_frames += 1
		app.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(frames.path_join("frame-%04d.png"%frame))==OK,"motion frame")
		if frame == 38: await snap("06-routes-small")
		if frame == 182: await snap("07-boss-small")
	check(moving_frames>120,"staged routes and Boss move in actual simulation")
	check(app.core.state=="playing","showcase survives 20 seconds")
	check(app.shape_cache.size()<128,"bounded glyph texture cache")
	print("FLOW_CAPTURE ",checks," checks, ",failed," failures; 240 frames / 12 fps; moving=",moving_frames," lives=",app.core.lives," cache=",app.shape_cache.size())
	app.queue_free()
	await process_frame
	quit(1 if failed else 0)
