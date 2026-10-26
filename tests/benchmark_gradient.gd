extends SceneTree
var app
func _initialize(): call_deferred("run")
func run():
	root.size=Vector2i(1920,1080)
	app=load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.muted=true
	app.set_process(false)
	app._start()
	app.core.debug_set_boss(3)
	for i in 540: app.core.step(1.0/120,Vector2.ZERO,true,true,false)
	app.visual_time=4.5
	var samples: Array[float]=[]
	for i in 90:
		var before=Time.get_ticks_usec()
		app.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		if i>=30:samples.append((Time.get_ticks_usec()-before)/1000.0)
	samples.sort()
	var total=0.0
	for x in samples:total+=x
	print("ISOLATED_RENDER_BENCH bullets=",app.core.bullets.size()," median_ms=",samples[30]," mean_ms=",total/60," p95_ms=",samples[57])
	app.free()
	await process_frame
	quit()
