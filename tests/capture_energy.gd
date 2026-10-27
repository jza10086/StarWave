extends SceneTree
## Real Compatibility render and input-flow verification; deterministic showcase.
var app
var output: String
var checks := 0
var failed := 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failed += 1
		push_error(label)
func key(code: int):
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	app._unhandled_input(event)
func snap(label: String):
	app.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label+".png")) == OK, label+" PNG")
func advance(ticks: int, move := Vector2.ZERO):
	for i in ticks:
		app.core.step(1.0/120,move,true,true,false)
		app.visual_time += 1.0/120
func run():
	output = OS.get_environment("CAPTURE_DIR")
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1440,960)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.muted = true
	app.set_process(false)
	await snap("01-title")
	key(KEY_ENTER)
	check(app.core.state == "playing", "Enter start")
	advance(1740,Vector2(.15,0))
	await snap("02-energy-waves")
	app._start()
	app.core.debug_set_boss(3)
	advance(540)
	check(app.core.focused,"precise focus")
	await snap("03-energy-boss")
	# Inspect actual generated texels: translucent load-bearing planes with luminous rims.
	var translucent_textures := 0
	var bright_textures := 0
	for cache_key in app.shape_cache:
		var tex: Image = app.shape_cache[cache_key].get_image()
		check(tex.has_mipmaps(), "generated glyph has mipmaps")
		var partial := 0
		var bright := 0
		var visible := 0
		for y in range(4,tex.get_height()-4,4):
			for x in range(4,tex.get_width()-4,4):
				var pixel := tex.get_pixel(x,y)
				if pixel.a > .01: visible += 1
				if pixel.a > .08 and pixel.a < .75: partial += 1
				if pixel.a > .75 and maxf(pixel.r,maxf(pixel.g,pixel.b)) > .75: bright += 1
		if partial > visible*.15: translucent_textures += 1
		if bright > 0: bright_textures += 1
	check(translucent_textures > 0, "load-bearing shapes have broad transparent colored planes")
	check(bright_textures > 0, "energy edges have bright solid accents")
	check(app.shape_cache.size() < 128, "bounded geometry palette after boss warmup")
	key(KEY_P)
	check(app.paused,"pause P")
	await snap("04-pause")
	key(KEY_ENTER)
	check(not app.paused,"resume Enter")
	key(KEY_X)
	check(app.core.bombs == 2 and app.core.bullets.is_empty(),"bomb clears bullets")
	app.bomb_flash = .42
	await snap("05-energy-pulse")
	key(KEY_P)
	key(KEY_R)
	check(not app.paused and app.core.lives == 3 and app.core.bombs == 3,"restart reset")
	await snap("06-restart")
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(app.paused,"focus loss pauses")
	key(KEY_ESCAPE)
	check(not app.paused,"Escape resumes")
	root.size = Vector2i(800,1000)
	await process_frame
	app._start()
	app.core.debug_set_boss(2)
	advance(360)
	await snap("07-portrait")
	root.size = Vector2i(1920,1080)
	await process_frame
	app._start()
	app.core.debug_set_boss(3)
	advance(540)
	await snap("08-landscape")
	# Warming deterministic full field, then sampling stable resources and render completion.
	# This software-render observation is not a platform performance promise.
	var cache_before: int = app.shape_cache.size()
	var objects_before := Performance.get_monitor(Performance.OBJECT_COUNT)
	var memory_before := Performance.get_monitor(Performance.MEMORY_STATIC)
	# Warm-up and frame-time sample include render completion; no image readback.
	var samples: Array[float] = []
	for i in 150:
		var before := Time.get_ticks_usec()
		app.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		if i >= 30: samples.append((Time.get_ticks_usec()-before)/1000.0)
	check(app.shape_cache.size() == cache_before, "steady scene creates no new glyph textures")
	check(Performance.get_monitor(Performance.OBJECT_COUNT) <= objects_before+16, "steady scene object count bounded")
	check(Performance.get_monitor(Performance.MEMORY_STATIC) <= memory_before+2097152, "steady scene memory bounded within 2 MiB")
	print("RESOURCE_SAMPLE cache=",app.shape_cache.size()," objects_delta=",Performance.get_monitor(Performance.OBJECT_COUNT)-objects_before," memory_delta=",Performance.get_monitor(Performance.MEMORY_STATIC)-memory_before)
	samples.sort()
	var total := 0.0
	for ms in samples: total += ms
	print("RENDER_BENCH 1920x1080 llvmpipe fixed boss bullets=",app.core.bullets.size()," mean_ms=",total/samples.size()," median_ms=",samples[60]," p95_ms=",samples[114])
	root.size = Vector2i(960,640)
	await process_frame
	app._start()
	app.core.debug_set_boss(3)
	var frames := output.path_join("energy-motion")
	DirAccess.make_dir_recursive_absolute(frames)
	for frame in 84:
		var direction := Vector2(-1 if frame > 25 and frame < 50 else 1 if frame >= 50 and frame < 72 else 0,0)
		advance(10,direction)
		app.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(frames.path_join("frame-%04d.png"%frame)) == OK, "motion frame saved")
	await snap("09-small")
	check(app.shape_cache.size() < 128, "shape texture cache remains bounded after movement / resizing")
	print("ENERGY_TEXTURE_CACHE entries=",app.shape_cache.size())
	print("ENERGY_CAPTURE ",checks," checks, ",failed," failures; 84 motion frames / 12 fps; lives=",app.core.lives)
	app.queue_free()
	await process_frame
	quit(1 if failed else 0)
