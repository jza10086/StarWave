extends SceneTree
## Geometry-only regression. Actual emission/readability is covered by capture_bullets.gd.
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
	var center := Vector2(240, 310)
	for sides in [3, 4, 6]:
		for angle in [0.0, PI / 6.0]:
			var pts: PackedVector2Array = app._poly(center, 23.0, sides, angle)
			check(pts.size() == sides, "correct vertex count")
			var regular := true
			var centroid := Vector2.ZERO
			for pt in pts:
				regular = regular and pt.is_finite() and absf(pt.distance_to(center) - 23.0) < 0.0001
				centroid += pt
			check(regular, "finite fixed-radius silhouette")
			check((centroid / sides).distance_to(center) < 0.0001, "centered silhouette")
	check(app.CYAN.g > .9 and app.CYAN.r < .4, "friendly cyan semantic")
	check(app.GOLD.r > .8 and app.GOLD.b < .6, "pickup gold semantic")
	check(app.INK.get_luminance() < .05, "dark background contrast")
	app._start()
	check(app.core.PLAYER_HIT_RADIUS == 4, "visual overhaul preserves hit radius")
	for phase in [1,2,3]:
		app.core.debug_set_boss(phase)
		check(app.core.boss.phase == phase and app.core.boss.radius == 58, "boss geometry does not alter collision")
	app.free()
	await process_frame
	print("NEON ART: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
