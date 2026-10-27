extends SceneTree
## Compare actual rendered pixels with internal waiting states on/off.
var app
var failed := 0
var checks := 0
var output: String
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failed += 1
		push_error(label)
func frame() -> Image:
	app.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func run():
	output = OS.get_environment("CAPTURE_DIR")
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1080,720)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	app.muted = true
	app.motion = false
	await process_frame
	for kind in ["scout","gunner","weaver","sniper","sweeper","orbiter","boss"]:
		app._start()
		app.core._boss_spawned = true
		var entity: Dictionary
		if kind == "boss":
			app.core.debug_set_boss(2)
			entity = app.core.boss
		else:
			app.core._spawn_enemy(kind,Vector2(app.FIELD.x*.5,240),0)
			entity = app.core.enemies[0]
		entity["telegraph"] = .7
		entity["attack_telegraph"] = .55
		entity["warning_angle"] = 1.1
		entity["gap_angle"] = 1.4
		entity["choreography_slot"] = 4
		var waiting: Image = await frame()
		entity["telegraph"] = 0.0
		entity["attack_telegraph"] = 0.0
		var ready: Image = await frame()
		check(waiting.get_data()==ready.get_data(),kind+": internal wait state has no visual overlay")
		check(waiting.save_png(output.path_join(kind+".png"))==OK,kind+": capture")
	check(not app.has_method("_attack_cue"),"explicit cue renderer removed")
	print("NO_WARNING_CAPTURE ",checks," checks, ",failed," failures")
	app.queue_free()
	await process_frame
	quit(1 if failed else 0)
