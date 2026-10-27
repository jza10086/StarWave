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
	await snap("02-gradient-waves")
	app._start()
	app.core.debug_set_boss(3)
	advance(540)
	check(app.core.focused,"precise focus")
	await snap("03-gradient-boss")
	var orb_textures := 0
	for cache_key in app.shape_cache:
		if not str(cache_key).begins_with("orb"): continue
		orb_textures += 1
		var orb: Image = app.shape_cache[cache_key].get_image()
		check(orb.get_size() == Vector2i(256,256), "high resolution orb texture")
		check(orb.has_mipmaps(), "orb minification mipmaps")
		check(orb.get_pixel(0,128).a == 0 and orb.get_pixel(128,0).a == 0, "transparent orb margins")
		check(orb.get_pixel(128,128).a > .99 and orb.get_pixel(12,128).a > .99, "solid orb interior reaches collision radius")
		var edge_alpha := false
		for x in range(6,12):
			for y in range(110,145):
				var a := orb.get_pixel(x,y).a
				edge_alpha = edge_alpha or (a > 0.0 and a < 1.0)
		check(edge_alpha, "orb boundary has antialiased coverage")
	check(orb_textures > 0, "real render created orb texture cache")
	# Test rendered SVG bytes rather than merely looking for gradient code.
	var polygon_textures := 0
	for cache_key in app.shape_cache:
		if str(cache_key).begins_with("orb"): continue
		var tex: Image = app.shape_cache[cache_key].get_image()
		if tex.get_width() < 160 or tex.get_height() < 160: continue
		polygon_textures += 1
		var lo := 1.0
		var hi := 0.0
		var levels := {}
		for y in range(int(tex.get_height()*.20),int(tex.get_height()*.80)):
			var pixel := tex.get_pixel(tex.get_width()/2,y)
			if pixel.a < .99: continue
			var value := maxf(pixel.r,maxf(pixel.g,pixel.b))
			lo = minf(lo,value)
			hi = maxf(hi,value)
			levels[int(value*255)] = true
		check(hi-lo > .12, "rendered polygon has visible interior gradient range")
		check(levels.size() > 24, "rendered polygon has continuous interior gradient levels")
	check(polygon_textures > 0, "real render sampled polygon gradients")
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
	# Warm-up and frame-time sample include render completion; no image readback.
	var samples: Array[float] = []
	for i in 150:
		var before := Time.get_ticks_usec()
		app.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		if i >= 30: samples.append((Time.get_ticks_usec()-before)/1000.0)
	samples.sort()
	var total := 0.0
	for ms in samples: total += ms
	print("RENDER_BENCH 1920x1080 llvmpipe fixed boss bullets=",app.core.bullets.size()," mean_ms=",total/samples.size()," median_ms=",samples[60]," p95_ms=",samples[114])
	root.size = Vector2i(960,640)
	await process_frame
	app._start()
	app.core.debug_set_boss(3)
	var frames := output.path_join("gradient-motion")
	DirAccess.make_dir_recursive_absolute(frames)
	for frame in 84:
		var direction := Vector2(-1 if frame > 25 and frame < 50 else 1 if frame >= 50 and frame < 72 else 0,0)
		advance(10,direction)
		app.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(frames.path_join("frame-%04d.png"%frame))
	check(app.shape_cache.size() < 100, "shape texture cache remains bounded after movement / resizing")
	print("SOFT_TEXTURE_CACHE entries=",app.shape_cache.size())
	print("GRADIENT_CAPTURE ",checks," checks, ",failed," failures; 84 motion frames / 12 fps; lives=",app.core.lives)
	app.queue_free()
	await process_frame
	quit(1 if failed else 0)
