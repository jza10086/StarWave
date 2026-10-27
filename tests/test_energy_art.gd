extends SceneTree
## Energy-symbol redesign contract. Legacy opaque-material tests are historical.
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func run():
	var app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.muted = true
	check(app.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "smooth linear mipmap sampling")
	check(app.light_canvas.z_index < 0, "radiance behind readable bodies")
	check(app.space_canvas.z_index < app.light_canvas.z_index, "atmosphere behind radiance")
	check(app.space_canvas.mouse_filter == Control.MOUSE_FILTER_IGNORE, "atmosphere cannot consume input")
	var edge := Image.create(8,8,false,Image.FORMAT_RGBA8)
	edge.fill(Color(0,0,0,0))
	edge.set_pixel(4,4,Color(.8,.3,.2,1))
	edge.set_pixel(3,4,Color(.7,.2,.1,.5))
	var solid := edge.get_pixel(4,4)
	var antialias := edge.get_pixel(3,4)
	app._bleed_transparent_rgb(edge,Color(.8,.4,.3))
	check(edge.get_pixel(0,0).a == 0.0, "bleed does not expose padding")
	check(edge.get_pixel(0,0).r > .5, "nonblack transparent RGB avoids dark halo")
	check(edge.get_pixel(4,4) == solid, "bleed preserves solid pixels")
	check(edge.get_pixel(3,4) == antialias, "bleed preserves partial coverage")
	app._start()
	check(app.core.PLAYER_HIT_RADIUS == 4.0, "precise hit point unchanged")
	check(app.core.PLAYER_SPEED == 350.0 and app.core.FOCUS_SPEED == 155.0, "movement speeds unchanged")
	check(app.core.lives == 3 and app.core.bombs == 3, "initial resources unchanged")
	for phase in [1,2,3]:
		app.core.debug_set_boss(phase)
		check(app.core.boss.phase == phase and app.core.boss.radius == 58, "boss phase and collision radius unchanged")
		check(app.core.boss.pos.is_finite(), "finite boss position")
	for size in [Vector2(1706.666667,960),Vector2(1440,1800),Vector2(1440,960)]:
		app.core.resize_field(size)
		check(app.core.field_size == size, "full adaptive field retained")
		check(Rect2(Vector2.ZERO,size).has_point(app.core.player), "player within resized field")
	check(app.CYAN.g > app.CYAN.r and app.CYAN.b > app.CYAN.r, "cool friendly hue")
	check(app.GOLD.r > app.GOLD.b, "gold pickup hue")
	app.free()
	await process_frame
	print("ENERGY ART: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
