extends SceneTree
## No-outline style contract plus rendering-independent gameplay invariants.
## Actual pixels and input interruption flows are verified by capture_gradient.gd.
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func function_body(source: String, name: String) -> String:
	var start := source.find("func " + name + "(")
	if start < 0: return ""
	var end := source.find("\nfunc ", start + 5)
	return source.substr(start) if end < 0 else source.substr(start, end - start)
func run():
	var source := FileAccess.get_file_as_string("res://scripts/main.gd")
	for name in ["_player", "_enemy", "_bullet"]:
		var body := function_body(source, name)
		check(not body.is_empty(), name + " renderer exists")
		for forbidden in ["draw_arc(", "draw_line(", "draw_polyline(", "_neon_ring(", "_neon_polygon(", "_neon_line("]:
			check(not body.contains(forbidden), name + " has no contour / stacked ring: " + forbidden)
	check(source.contains("_soft_orb("), "smooth filled bullet helper")
	check(source.contains("_soft_polygon("), "filled silhouette helper")
	for name in ["_soft_orb", "_soft_polygon"]:
		var body := function_body(source, name)
		check(body.contains("load_svg_from_string(svg,4.0)"), name + " high-resolution 4x rasterization")
		check(body.contains("generate_mipmaps()"), name + " minification mipmaps")
		check(body.find("_bleed_transparent_rgb(img,col)") >= 0 and body.find("_bleed_transparent_rgb(img,col)") < body.find("generate_mipmaps()"), name + " transparent RGB bleed before minification")
		check(not body.contains("stroke="), name + " no SVG stroke")
		check(body.contains("shape_cache.has(key)"), name + " reused texture cache")
	check(function_body(source,"_soft_orb").contains('<circle cx="32" cy="32" r="30"'), "analytic circular bullet silhouette, no faceted core")
	check(function_body(source,"_soft_orb").contains("r*32.0/30.0"), "opaque circle maps to unchanged collision radius")
	check(not function_body(source,"_space").contains("draw_polyline("), "background has no angular wire fragments")
	var app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.muted = true
	var edge := Image.create(8,8,false,Image.FORMAT_RGBA8)
	edge.fill(Color(0,0,0,0))
	edge.set_pixel(4,4,Color(.8,.3,.2,1))
	edge.set_pixel(3,4,Color(.7,.2,.1,.5))
	var opaque_before := edge.get_pixel(4,4)
	var partial_before := edge.get_pixel(3,4)
	app._bleed_transparent_rgb(edge,Color(.8,.4,.3))
	check(edge.get_pixel(0,0).a == 0.0 and edge.get_pixel(7,7).a == 0.0, "padding remains fully transparent")
	check(edge.get_pixel(0,0).r > .5 and edge.get_pixel(7,7).r > .5, "entire padding has nonblack RGB to prevent mip fringes")
	check(edge.get_pixel(4,4) == opaque_before, "RGB bleed preserves opaque art")
	check(edge.get_pixel(3,4) == partial_before, "RGB bleed preserves antialiased edge coverage")
	check(app.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "linear filtering, not nearest")
	check(app.light_canvas.z_index < 0, "decorative glow behind collision silhouettes")
	check(app.CYAN.g > app.CYAN.r and app.CYAN.b > app.CYAN.r, "friendly cool mint semantic")
	check(app.GOLD.r > app.GOLD.b and app.GOLD.g > app.GOLD.b, "warm gold pickup semantic")
	app._start()
	check(app.core.PLAYER_HIT_RADIUS == 4.0, "unchanged precise hit radius")
	check(app.core.PLAYER_SPEED == 350.0 and app.core.FOCUS_SPEED == 155.0, "unchanged normal / focus movement")
	check(app.core.lives == 3 and app.core.bombs == 3, "unchanged starting resources")
	for phase in [1,2,3]:
		app.core.debug_set_boss(phase)
		check(app.core.boss.phase == phase and app.core.boss.radius == 58, "unchanged boss phase / collision radius")
	app.free()
	await process_frame
	print("SOFT ART: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
