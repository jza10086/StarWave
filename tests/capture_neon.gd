extends SceneTree
var app
func _initialize(): call_deferred("run")
func run():
	var output=OS.get_environment("CAPTURE_DIR")
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1440,960)
	app=load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.muted=true
	app.set_process(false)
	app._start()
	# Deterministic real simulation, no inserted entities or compositing.
	for i in range(1740): app.core.step(1.0/120,Vector2(sin(i*.004),0),true,true,false)
	app.visual_time=14.5
	app.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("12-neon-waves.png"))
	app._start()
	app.core.debug_set_boss(3)
	for i in range(540): app.core.step(1.0/120,Vector2.ZERO,true,true,false)
	app.visual_time=4.5
	app.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("13-neon-boss.png"))
	print("NEON_SHOWCASE_DONE bullets=",app.core.bullets.size()," shots=",app.core.shots.size())
	root.size=Vector2i(960,640)
	await process_frame
	app._start()
	app.core.debug_set_boss(3)
	var frames=output.path_join("neon-motion")
	DirAccess.make_dir_recursive_absolute(frames)
	for frame in range(84):
		var direction=Vector2(-1 if frame>25 and frame<50 else 1 if frame>=50 and frame<72 else 0,0)
		for tick in range(10): app.core.step(1.0/120,direction,true,true,false)
		app.visual_time+=1.0/12
		app.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(frames.path_join("frame-%04d.png"%frame))
	print("NEON_MOTION_DONE 84 frames / 12 fps; lives=",app.core.lives)
	app.queue_free()
	await process_frame
	quit()
