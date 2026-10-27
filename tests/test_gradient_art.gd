extends SceneTree
## Continuous falloffs and isolated render layers, independent of combat logic.
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
	check(app.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,"linear light sampling")
	check(app.light_canvas.material.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD,"additive bounded aura")
	check(app.light_canvas.z_index < 0,"auras behind crisp geometry")
	check(app.space_canvas.z_index < app.light_canvas.z_index,"background behind emission")
	check(app.space_canvas.mouse_filter == Control.MOUSE_FILTER_IGNORE,"shader cannot intercept input")
	check(app.space_canvas.material.shader != null,"procedural background shader")
	var glow: Image = app.aura.get_image()
	check(glow.get_size() == Vector2i(128,128),"bounded precomputed aura texture")
	check(glow.get_pixel(64,64).a > .99,"radiant aura center")
	check(glow.get_pixel(0,64).a < .001,"seamless aura horizontal edge")
	check(glow.get_pixel(64,0).a < .001,"seamless aura vertical edge")
	var unique := {}
	var monotonic := true
	var previous := 1.0
	for x in range(64,128):
		var a := glow.get_pixel(x,64).a
		unique[a] = true
		monotonic = monotonic and a <= previous
		previous = a
	check(monotonic,"smooth monotonic radial falloff")
	check(unique.size() > 40,"continuous sampled aura, not layered flat bands")
	var beam: Image = app.beam.get_image()
	check(beam.get_size() == Vector2i(128,32),"small reusable beam texture")
	check(beam.get_pixel(64,16).a > .96,"bright beam spine")
	check(beam.get_pixel(64,0).a < .001,"soft beam border")
	check(beam.get_pixel(0,16).a < .01,"soft beam cap")
	var ring: Image = app.energy_ring.get_image()
	check(ring.get_pixel(64,64).a < .001,"shockwave hollow center")
	check(ring.get_pixel(110,64).a > .95,"shockwave radiant annulus")
	check(ring.get_pixel(127,64).a < .001,"shockwave fades before texture boundary")
	app._start()
	check(app.core.PLAYER_HIT_RADIUS == 4,"precise hit radius retained")
	app.free()
	await process_frame
	print("GRADIENT ART: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
