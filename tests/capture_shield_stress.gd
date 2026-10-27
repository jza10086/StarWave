extends SceneTree
## Controlled density fixture, NOT ordinary gameplay: 384 stationary ring bullets
## and one real collision trigger. Native renderer; no composited or edited pixels.
const Core = preload("res://scripts/game_core.gd")
var app
var caption: Label
var output: String
var checks := 0
var failures := 0
var peak_remnants := 0
func _initialize(): call_deferred("run")
func check(ok: bool,label: String):
	checks += 1
	if not ok: failures += 1; push_error(label)
func advance(ticks: int):
	for i in ticks:
		app.core.step(1.0/120,Vector2.ZERO,false,false,false)
		app.visual_time += 1.0/120
		peak_remnants=maxi(peak_remnants,app.core.cancel_effects.size())
		if not app.core.damage_waves.is_empty():
			var wave: Dictionary=app.core.damage_waves[0]
			for b in app.core.bullets:
				check(Vector2(b.pos).distance_to(wave.pos)>wave.radius+b.radius-.05,"retained danger remains ahead of swept front")
		check(app.core.cancel_effects.size()<=Core.MAX_CANCEL_EFFECTS,"native stress respects remnant cap")
func snap(name: String):
	caption.text="CONTROLLED DENSITY FIXTURE\n385 bullets / real collision trigger\nDanger: %d   Dissolving: %d"%[app.core.bullets.size(),app.core.cancel_effects.size()]
	app.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var img: Image=root.get_texture().get_image()
	check(img.save_png(output.path_join(name+".png"))==OK,"save "+name)
	var bright := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var col: Color=img.get_pixel(x,y)
			if minf(col.r,minf(col.g,col.b))>.75: bright += 1
	var ratio := float(bright)/(img.get_width()*img.get_height())
	print("NATIVE_STRESS_FRAME ",name," danger=",app.core.bullets.size()," remnants=",app.core.cancel_effects.size()," neutral_bright_pixel_fraction=",ratio)
	check(ratio<.025,"no broad neutral-white flood "+name)
func run():
	output=OS.get_environment("CAPTURE_DIR")
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1440,960)
	app=load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.muted=true; app.set_process(false)
	await process_frame
	app._start()
	# Fixture initialization only; all hit detection and cancellation use core.step.
	app.core._boss_spawned=true
	app.core.invulnerable=0.0
	app.core.player=Vector2(720,480)
	for row in 8:
		for spoke in 48:
			var pos: Vector2=app.core.player+Vector2.from_angle(TAU*spoke/48.0)*(420+row*6)
			app.core._add_bullet(pos,Vector2.ZERO,5,Core.PINK if spoke%2==0 else Core.PURPLE)
	app.core._add_bullet(app.core.player,Vector2.ZERO,5,Core.GOLD)
	caption=Label.new()
	caption.position=Vector2(300,490); caption.size=Vector2(840,100)
	caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_override("font",app.FONT)
	caption.add_theme_font_size_override("font_size",20)
	caption.modulate=Color("7caaa9")
	app.add_child(caption)
	check(app.core.bullets.size()==385,"385 bullet controlled setup")
	await snap("controlled-before-385")
	advance(1)
	check(app.core.lives==2 and app.core.bullets.size()==384 and app.core.damage_waves.size()==1,"real collision removes only impact bullet initially")
	while float(app.core.damage_waves[0].radius)<400.0: advance(1)
	check(app.core.bullets.size()==384,"384 distant bullets remain until visible wave reaches them")
	await snap("controlled-wave-before-contact")
	while float(app.core.damage_waves[0].radius)<440.0: advance(1)
	check(app.core.bullets.size()>0 and app.core.bullets.size()<384,"partial sweep leaves unreached ring rows dangerous")
	await snap("controlled-wave-partial")
	while float(app.core.damage_waves[0].radius)<470.0: advance(1)
	check(app.core.bullets.is_empty() and app.core.cancel_effects.size()==384 and peak_remnants==384,"384 simultaneous individually cancelled remnants")
	check(app.core.lives==2 and app.core.bombs==3,"density sweep does not use pulse or extra lives")
	await snap("controlled-peak-384-remnants")
	advance(int(ceil((Core.DAMAGE_WAVE_DURATION+Core.CANCEL_EFFECT_DURATION)*120))+2)
	check(app.core.cancel_effects.is_empty() and app.core.damage_waves.is_empty() and app.core._cancel_pool.size()<=384,"stress wave and remnants expire into bounded pool")
	print("SHIELD_STRESS ",checks," checks, ",failures," failures; controlled_fixture=true; initial_bullets=385; peak_remnants=",peak_remnants,"; native=1440x960 Compatibility")
	app.queue_free(); await process_frame
	quit(1 if failures else 0)
