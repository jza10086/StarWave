extends SceneTree
var app
var output := ""
func _initialize(): call_deferred("run")
func key(code: int, down: bool):
	var e=InputEventKey.new()
	e.keycode=code
	e.pressed=down
	Input.parse_input_event(e)
func snap(label: String):
	await create_timer(.25).timeout
	await RenderingServer.frame_post_draw
	var img=root.get_texture().get_image()
	print("CAPTURE ",label," ",img.get_size()," result=",img.save_png(output.path_join(label+".png")))
func run():
	output=OS.get_environment("CAPTURE_DIR")
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1080,720)
	app=load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.muted=true
	await snap("01-title")
	app._start()
	app.core.debug_set_boss(2)
	key(KEY_SHIFT,true)
	await snap("02-boss-telegraph")
	await create_timer(2.0).timeout
	await snap("03-boss-focus")
	app.paused=true
	root.size=Vector2i(960,640)
	app.paused=false
	await snap("04-small-focus")
	app.paused=true
	root.size=Vector2i(1920,1080)
	app.paused=false
	await snap("05-large-focus")
	root.size=Vector2i(960,640)
	app._start()
	app.core.debug_set_boss(3)
	app.auto_fire=false
	key(KEY_SHIFT,true)
	var images=[]
	var stamps=[]
	var start=Time.get_ticks_msec()
	while Time.get_ticks_msec()-start<6500:
		var t=Time.get_ticks_msec()-start
		key(KEY_A,t>2200 and t<4000)
		key(KEY_D,t>=4000 and t<5600)
		await RenderingServer.frame_post_draw
		images.append(root.get_texture().get_image())
		stamps.append({"frame":images.size()-1,"ms":Time.get_ticks_msec()-start,"bullets":app.core.bullets.size(),"lives":app.core.lives})
		await create_timer(.066).timeout
	key(KEY_A,false)
	key(KEY_D,false)
	key(KEY_SHIFT,false)
	var d=output.path_join("boss-frames")
	DirAccess.make_dir_recursive_absolute(d)
	for i in images.size(): images[i].save_png(d.path_join("frame-%04d.png"%i))
	FileAccess.open(d.path_join("timing.json"),FileAccess.WRITE).store_string(JSON.stringify(stamps))
	print("MOTION frames=",images.size()," lives=",app.core.lives)
	await snap("06-boss-pattern")
	key(KEY_X,true)
	key(KEY_X,false)
	await snap("07-bomb-effect")
	# Menu centering and full-viewport expansion at different aspect ratios.
	key(KEY_P,true)
	key(KEY_P,false)
	await snap("08-pause")
	key(KEY_R,true)
	key(KEY_R,false)
	await snap("09-restart")
	root.size=Vector2i(800,1000)
	app.paused=false
	await snap("10-portrait")
	root.size=Vector2i(1920,1080)
	app.paused=false
	app.core.debug_set_boss(3)
	app.core.boss.telegraph=0
	for i in range(360):
		app.core.step(1.0/120,Vector2.ZERO,false,true,false)
	await snap("11-wide-pattern")
	app.queue_free()
	await process_frame
	print("CAPTURE_DONE")
	quit()
