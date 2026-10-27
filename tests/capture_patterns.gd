extends SceneTree
## Actual Compatibility renderer; staged role showcase + continuous boss simulation.
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
func enemy_scene():
	app._start()
	# Deliberately arranged role gallery; all motion / attacks still use real core rules.
	app.core._boss_spawned = true
	var types := ["sniper","sweeper","orbiter"]
	for i in 3: app.core._spawn_enemy(types[i],Vector2(app.FIELD.x*(.25+i*.25),150+i%2*55),i)
	advance(330)
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
	advance(510)
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
	advance(510)
	await snap("05-boss-portrait")
	root.size = Vector2i(960,640)
	await process_frame
	app.core.debug_set_boss(2)
	var frames := output.path_join("patterns-motion")
	DirAccess.make_dir_recursive_absolute(frames)
	var previous: float = app.core.boss.rotation
	var moved := 0
	for frame in 144:
		advance(10)
		if absf(app.core.boss.rotation-previous)>.001: moved += 1
		previous = app.core.boss.rotation
		app.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(frames.path_join("frame-%04d.png"%frame))==OK,"motion frame")
	check(moved>=140,"blade motion continuous except eased direction reversal")
	check(app.core.state=="playing","showcase survives 12 seconds")
	check(app.shape_cache.size()<128,"bounded glyph texture cache")
	print("PATTERNS_CAPTURE ",checks," checks, ",failed," failures; 144 frames / 12 fps; lives=",app.core.lives," cache=",app.shape_cache.size())
	app.queue_free()
	await process_frame
	quit(1 if failed else 0)
