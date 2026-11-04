extends Node2D

const Core: Variant = preload("res://games/minigame/godot_party_default_star_wave/game_core.gd")
const FONT: Variant = preload("res://games/protocols/godot_party_default_protocol/fonts/NotoSansSC-UI.otf")
const ORIGIN: Variant = Vector2.ZERO
var FIELD: Variant = Vector2(1440, 960)
const CYAN: Variant = Color("62ebda")
const GOLD: Variant = Color("f4d88f")
const INK: Variant = Color("050718")
var core: Variant = Core.new()
var paused: Variant = false
var auto_fire: Variant = true
var motion: Variant = true
var muted: Variant = false
var visual_time: Variant = 0.0
var bomb_flash: Variant = 0.0
var last_lives: Variant = 3
var last_score: Variant = 0
var sounds: Dictionary = {}
var audio: AudioStreamPlayer
var pointer_active: Variant = false
var shape_cache: Dictionary = {}
var hit_white: float = 0.0
var aura: ImageTexture
var beam: ImageTexture
var shot_heads: MultiMesh
var ribbons: MultiMesh
var ribbon_count: int = 0
var energy_ring: ImageTexture
@onready var light_canvas: Node2D = $LightPass
@onready var space_canvas: ColorRect = $DeepSpace
var curve_indices: PackedInt32Array = PackedInt32Array()
var trail_indices: PackedInt32Array = PackedInt32Array()
var curve_points: PackedVector2Array = PackedVector2Array()
var curve_colors: PackedColorArray = PackedColorArray()
var curve_batch_indices: PackedInt32Array = PackedInt32Array()


# Feedback has a local clock: a repeated network snapshot cannot restart a flash.
var feedback_id: int = 0
var feedback_effects: Array[Dictionary] = []
var hit_poses: Dictionary = {}
var shake_age: float = 0.0
var shake_duration: float = 0.0
var shake_strength: float = 0.0
var feedback_audio: AudioStreamPlayer
var sound_cooldown: float = 0.0

func consume_feedback(events: Array) -> void:
	var hits: Dictionary = {}
	var sound: String = ""
	for event: Dictionary in events:
		if int(event.feedback_id) <= feedback_id:
			continue
		feedback_id = int(event.feedback_id)
		if event.type == "hit":
			var id: int = event.target_id
			if hits.has(id):
				hits[id].damage += float(event.damage)
			else:
				hits[id] = event.duplicate()
			continue
		var effect: Dictionary = event.duplicate()
		effect.age = 0.0
		feedback_effects.append(effect)
		if event.type == "phase":
			_boss_shake(4.0, 0.32)
			sound = "phase"
		elif event.type == "victory":
			_boss_shake(8.0, 0.55)
			sound = "clear"
		elif event.type == "explosion" and sound.is_empty():
			sound = "break"
	for id: int in hits:
		var hit: Dictionary = hits[id]
		hit.age = 0.0
		hit.life = 0.48
		feedback_effects.append(hit)
		hit_poses[id] = {"age": 0.0, "direction": hit.direction}
		if hit.boss_hit:
			_boss_shake(1.3, 0.13)
		if sound.is_empty():
			sound = "hit"
	while feedback_effects.size() > 90:
		feedback_effects.pop_front()
	if not sound.is_empty() and sound_cooldown <= 0.0 and not muted and is_visible_in_tree():
		feedback_audio.stream = sounds[sound]
		feedback_audio.play()
		sound_cooldown = 0.065 if sound == "hit" else 0.12

func advance_feedback(delta: float) -> void:
	sound_cooldown = maxf(0.0, sound_cooldown - delta)
	for index: int in range(feedback_effects.size() - 1, -1, -1):
		feedback_effects[index].age += delta
		if feedback_effects[index].age >= feedback_effects[index].life:
			feedback_effects.remove_at(index)
	for id: int in hit_poses.keys():
		hit_poses[id].age += delta
		if hit_poses[id].age >= 0.26:
			hit_poses.erase(id)
	shake_age += delta
	var offset: Vector2 = Vector2.ZERO
	if shake_age < shake_duration:
		var envelope: float = pow(1.0 - shake_age / shake_duration, 2.0)
		offset = Vector2(sin(visual_time * 83.0), sin(visual_time * 107.0)) * shake_strength * envelope
	position = offset * scale
	# Keep the background covering the entire surface and HUD anchored to the screen.
	space_canvas.position = -offset

func _boss_shake(strength: float, duration: float) -> void:
	var remaining_strength: float = shake_strength * maxf(0.0, 1.0 - shake_age / maxf(shake_duration, 0.001))
	if strength >= remaining_strength:
		shake_age = 0.0
		shake_duration = duration
		shake_strength = strength

# Generated once. Gaussian alpha is continuous, not concentric solid bands.
func _make_light_texture(kind: int) -> ImageTexture:
	var size: Variant = Vector2i(128, 128) if kind != 1 else Vector2i(128, 32)
	var img: Variant = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y: Variant in range(size.y):
		for x: Variant in range(size.x):
			var uv: Variant = Vector2((x+.5)/size.x, (y+.5)/size.y) * 2.0 - Vector2.ONE
			var r: Variant = uv.length()
			var alpha: Variant = exp(-r*r*5.5) * (1.0-smoothstep(.75,1.0,r))
			if kind == 1: alpha = exp(-uv.y*uv.y*6.0) * (1.0-smoothstep(.7,1.0,absf(uv.y))) * (1.0-smoothstep(.75,1.0,absf(uv.x)))
			if kind == 2: alpha = exp(-pow((r-.72)/.065,2)) * (1.0-smoothstep(.95,1.0,r))
			img.set_pixel(x,y,Color(1,1,1,alpha))
	return ImageTexture.create_from_image(img)

func _setup_lighting() -> void:
	aura = _make_light_texture(0)
	beam = _make_light_texture(1)
	energy_ring = _make_light_texture(2)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	light_canvas.draw.connect(_light_pass)

func _aura_at(p: Vector2, radius: Vector2, col: Color) -> void:
	light_canvas.draw_texture_rect(aura,Rect2(p-radius,radius*2),false,col)

func _light_pass() -> void:
	for e: Variant in core.enemies:
		var col: Variant = Color("eeb66c") if e.type=="gunner" else Color("af88e7") if e.type=="weaver" else Color("e67eaa")
		_aura_at(e.pos,Vector2.ONE*e.radius*3.4,Color(col,.12))
	if not core.boss.is_empty() and float(core.boss.hp) > 0.0:
		var p: Vector2 = core.boss.pos
		_aura_at(p,Vector2(220,160),Color(.47,.24,1,.24))
	for shot: Variant in core.shots: _aura_at(shot.pos,Vector2(13,30),Color(CYAN,.27))
	for b: Variant in core.bullets:
		var original: Color = b.get("color",Color("ff70c8"))
		var col: Variant = Color("e67eaa") if original.r>original.b else Color("bc85f5")
		if original.g>.65 and original.r>.8: col=Color("ffc16a")
		_aura_at(b.pos,Vector2.ONE*b.get("radius",6)*3.4,Color(col,.09))
	for pick: Variant in core.pickups: _aura_at(pick.pos,Vector2(42,42),Color(GOLD,.24))
	for id: String in core.pilots:
		var pilot: Dictionary = core.pilots[id]
		if pilot.lives <= 0:
			continue
		var position_value: Vector2 = core.pilot_draw_positions[id]
		_aura_at(position_value, Vector2(65, 65), Color(Color(pilot.color), 0.18))
		_aura_at(position_value + Vector2(0, 34), Vector2(40, 70), Color(0.15, 0.45, 1, 0.22))
	for effect: Variant in feedback_effects:
		var a: Variant = clampf(1.0-effect.get("age",0)/maxf(effect.get("life",.5),.001),0,1)
		_aura_at(effect.pos,Vector2.ONE*effect.get("radius",24)*3,Color(CYAN,a*.28))


func _ready() -> void:
	# Shared topology for two feathered halves across twelve curved-wake segments.
	for segment: int in 12:
		var base: int = segment * 3
		curve_indices.append_array(PackedInt32Array([base, base + 3, base + 4, base, base + 4, base + 1,
			base, base + 5, base + 3, base, base + 2, base + 5]))
	trail_indices = curve_indices.slice(0, 96)
	_setup_lighting()
	_setup_ribbons()
	_setup_shot_heads()
	audio = AudioStreamPlayer.new()
	audio.volume_db = -18
	add_child(audio)
	feedback_audio = AudioStreamPlayer.new()
	feedback_audio.volume_db = -22
	feedback_audio.max_polyphony = 3
	add_child(feedback_audio)
	for kind: String in ["start", "bomb", "hurt", "clear", "hit", "break", "phase"]:
		sounds[kind] = _make_sound(kind)
	set_process(false)

func _draw() -> void:
	_background()
	light_canvas.queue_redraw()
	_field()

func _text(pos: Vector2, value: String, size: int = 20, color: Color = Color("b5c5df")) -> void:
	draw_string(FONT, pos, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _center(pos: Vector2, value: String, size: int, color: Color) -> void:
	_text(pos - Vector2(FONT.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * 0.5, 0), value, size, color)

func _resize_field() -> void:
	FIELD = get_viewport_rect().size
	core.resize_field(FIELD)
	queue_redraw()

func _background() -> void:
	space_canvas.size = FIELD
	space_canvas.material.set_shader_parameter("drift", visual_time if motion else 0.0)

# Smooth sampled falloff plus a crisp silhouette; additive aura lives behind geometry.
func _neon_line(a: Vector2, b: Vector2, color: Color, width: float = 2.0) -> void:
	var dir: Variant = (b-a).normalized()
	var side: Variant = dir.orthogonal()*(width+12)*.5
	var pts: Variant = PackedVector2Array([a-dir*5-side,b+dir*5-side,b+dir*5+side,a-dir*5+side])
	draw_polygon(pts,PackedColorArray([Color(color,color.a*.38)]),PackedVector2Array([Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]),beam)
	draw_line(a,b,color,width,true)

func _poly(p: Vector2, radius: float, sides: int, angle: float = 0.0) -> PackedVector2Array:
	var pts: Variant = PackedVector2Array()
	for i: Variant in range(sides): pts.append(p + Vector2.from_angle(angle + TAU*i/sides)*radius)
	return pts

# Transparent colored planes and alpha falloff, rasterized at 4x. No black contours.
# Keys are local geometry + palette only: movement never allocates textures.
func _bleed_transparent_rgb(img: Image, col: Color) -> void:
	# Transparent black leaks into RGB mip averages unless the entire padding is filled.
	for y: Variant in img.get_height():
		var edge_color: Variant = col.lightened(.15).lerp(col.darkened(.18),float(y)/img.get_height())
		for x: Variant in img.get_width():
			if img.get_pixel(x,y).a == 0.0:
				img.set_pixel(x,y,Color(edge_color,0))

func _soft_polygon(pts: PackedVector2Array, col: Color) -> void:
	var bounds: Variant = Rect2(pts[0],Vector2.ZERO)
	for pt: Variant in pts: bounds = bounds.expand(pt)
	var points: Variant = ""
	for pt: Variant in pts:
		var local: Variant = pt-bounds.position+Vector2.ONE*2
		points += "%.2f,%.2f " % [local.x,local.y]
	var key: Variant = points+col.to_html(false)
	if not shape_cache.has(key):
		var size: Variant = bounds.size+Vector2.ONE*4
		# Explicit pixel-space coordinates avoid renderer-dependent objectBoundingBox units.
		# Frame stays inside the original silhouette: clip the wide colored stroke.
		var svg: Variant = '<svg xmlns="http://www.w3.org/2000/svg" width="%s" height="%s"><defs><linearGradient id="v" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="%s" y2="%s"><stop stop-color="#%s" stop-opacity="0.38"/><stop offset="0.55" stop-color="#%s" stop-opacity="0.18"/><stop offset="1" stop-color="#%s" stop-opacity="0.05"/></linearGradient><clipPath id="shape"><polygon points="%s"/></clipPath></defs><polygon points="%s" fill="url(#v)"/><polygon points="%s" fill="none" stroke="#%s" stroke-opacity="0.95" stroke-width="2.6" stroke-linejoin="round" clip-path="url(#shape)"/></svg>' % [size.x,size.y,size.x*.35,size.y,col.to_html(false),col.to_html(false),col.to_html(false),points,points,points,col.lightened(.56).to_html(false)]
		var img: Variant = Image.new()
		img.load_svg_from_string(svg,4.0)
		_bleed_transparent_rgb(img,col)
		img.generate_mipmaps()
		shape_cache[key] = ImageTexture.create_from_image(img)
	draw_texture_rect(shape_cache[key],Rect2(bounds.position-Vector2.ONE*2,bounds.size+Vector2.ONE*4),false,Color(1,1,1,col.a))
	if hit_white > 0.0:
		draw_colored_polygon(pts, Color(1, 1, 1, hit_white * col.a))

func _soft_orb(p: Vector2, r: float, col: Color) -> void:
	var key: Variant = "orb"+col.to_html(false)
	if not shape_cache.has(key):
		# Flat colored energy disc with luminous circumference; no sphere lighting or specular spot.
		var svg: Variant = '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><circle cx="32" cy="32" r="30" fill="#%s" fill-opacity="0.68"/><circle cx="32" cy="32" r="27.8" fill="none" stroke="#%s" stroke-width="4.4"/></svg>' % [col.to_html(false),col.lightened(.65).to_html(false)]
		var img: Variant = Image.new()
		img.load_svg_from_string(svg,4.0)
		_bleed_transparent_rgb(img,col)
		img.generate_mipmaps()
		shape_cache[key] = ImageTexture.create_from_image(img)
	var extent: Variant = r*32.0/30.0
	draw_texture_rect(shape_cache[key],Rect2(p-Vector2.ONE*extent,Vector2.ONE*extent*2),false,Color(1,1,1,col.a))
	if hit_white > 0.0:
		draw_circle(p, r, Color(1, 1, 1, hit_white * col.a), true, -1, true)

func _neon_ring(p: Vector2, radius: float, color: Color, width: float = 1.5, start: float = 0, end: float = TAU) -> void:
	# Annular Gaussian is used for full energy rings; arcs remain fine, clean cores.
	if end-start >= TAU-.01 and radius>8:
		var extent: Variant = radius/.72
		draw_texture_rect(energy_ring,Rect2(p-Vector2.ONE*extent,Vector2.ONE*extent*2),false,Color(color,color.a*.34))
	draw_arc(p,radius,start,end,96,color,width,true)

func _space() -> void:
	var t: Variant = visual_time if motion else 0.0
	# Small continuous light discs, never single-pixel squares or wire fragments.
	for i: Variant in range(int(FIELD.x*FIELD.y/14000)):
		var pos: Variant = Vector2(fmod(i*137.71,FIELD.x-14)+7,fmod(i*73.31+t*(5+i%4*3),FIELD.y-4)+2)
		draw_texture_rect(aura,Rect2(pos-Vector2.ONE*2.5,Vector2.ONE*5),false,Color(.68,.73,.88,.22+float(i%3)*.08))

func _field() -> void:
	ribbon_count = 0
	_space()
	var shot_count: int = 0
	for shot: Dictionary in core.shots:
		var p: Vector2 = shot.pos
		if not Rect2(Vector2(5, 0), FIELD - Vector2(10, 0)).has_point(p):
			continue
		_ribbon(p + Vector2(0, 4), Vector2.DOWN, 80, 8, Color(CYAN, 0.42), sin(p.x * 0.07))
		shot_heads.set_instance_transform_2d(shot_count, Transform2D(0.0, p))
		shot_count += 1
	shot_heads.visible_instance_count = shot_count

	for e: Variant in core.enemies: _enemy(e)
	if not core.boss.is_empty() and float(core.boss.hp) > 0.0: _enemy(core.boss)
	for pick: Variant in core.pickups:
		var p: Vector2 = pick.pos
		_soft_polygon(_poly(p,17,4,-PI/2),GOLD)
		_center(p+Vector2(0,5),"P" if pick.get("type","power")=="power" else "B",14,Color("fff1ce"))
	for effect: Variant in feedback_effects: _impact(effect)
	for shield: Variant in core.damage_waves: _damage_shield(shield)
	for remnant: Variant in core.cancel_effects: _bullet_cancel(remnant)
	curve_points.clear()
	curve_colors.clear()
	for bullet: Dictionary in core.bullets:
		_bullet_wake(bullet)
	if not curve_points.is_empty():
		var index_count: int = curve_points.size() / 39 * 144
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), curve_batch_indices.slice(0, index_count), curve_points, curve_colors)
	for bullet: Dictionary in core.bullets:
		_bullet(bullet)
	for id: String in core.pilots:
		var pilot: Dictionary = core.pilots[id]
		if pilot.lives <= 0: continue
		core.player = core.pilot_draw_positions[id]
		core.invulnerable = pilot.invulnerable
		core.focused = pilot.focus
		_player(Color(pilot.color))
	ribbons.visible_instance_count = ribbon_count

	if bomb_flash > 0:
		draw_rect(Rect2(Vector2.ZERO,FIELD),Color(.3,1,.93,bomb_flash*.10))
		_neon_ring(core.player,maxf(0,(.65-bomb_flash)*1600),Color(CYAN,bomb_flash*.85),2)

func _trail(p: Vector2, dir: Vector2, length: float, width: float, col: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	var colors: PackedColorArray = PackedColorArray()
	points.resize(27)
	colors.resize(27)
	for sample_index: int in 9:
		var progress: float = float(sample_index) / 8.0
		var center: Vector2 = p + dir * length * progress
		var side: Vector2 = dir.orthogonal() * width * (1.0 - progress)
		var index: int = sample_index * 3
		points[index] = center
		points[index + 1] = center - side
		points[index + 2] = center + side
		colors[index] = Color(col, col.a * pow(1.0 - progress, 1.7))
		colors[index + 1] = Color(col, 0.0)
		colors[index + 2] = Color(col, 0.0)
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), trail_indices, points, colors)

func _impact(effect: Dictionary) -> void:
	var age: float = effect.age
	var progress: float = clampf(age / float(effect.life), 0.0, 1.0)
	var fade: float = 1.0 - progress
	if fade < 0.01:
		return
	var p: Vector2 = effect.pos
	if effect.type == "hit":
		# Open streaks and a short white glint never look like hostile bullet cores.
		var spark_fade: float = maxf(0.0, 1.0 - age / 0.22)
		var incoming: Vector2 = effect.direction
		for index: int in 5:
			var direction: Vector2 = (-incoming).rotated((index - 2) * 0.5)
			var tip: Vector2 = p + direction * (8.0 + age * (135.0 + index * 18.0))
			draw_line(tip, tip - direction * 12.0 * spark_fade, Color(GOLD, spark_fade), 1.5, true)
		if age < 0.055:
			draw_line(p - Vector2(11, 0), p + Vector2(11, 0), Color(1, 1, 1, spark_fade), 2.0, true)
			draw_line(p - Vector2(0, 7), p + Vector2(0, 7), Color(1, 1, 1, spark_fade), 2.0, true)
		var label: String = str(ceili(float(effect.damage)))
		var at: Vector2 = p + Vector2(22, -22 - 54 * progress)
		draw_string_outline(FONT, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, 3, Color(INK, fade))
		draw_string(FONT, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color("fff3cf", fade))
		return
	var burst: bool = effect.type in ["explosion", "victory"]
	var color: Color = GOLD if burst else CYAN
	var radius: float = float(effect.radius) * (0.25 + 1.1 * (1.0 - pow(1.0 - progress, 3.0)))
	_neon_ring(p, radius, Color(color, fade * fade * 0.75), 1.6)
	if burst or effect.type == "phase":
		_neon_ring(p, radius * 0.68, Color("bf9aff", fade * 0.35), 1.0)
		var count: int = 16 if effect.type == "victory" else 9
		for index: int in count:
			var direction: Vector2 = Vector2.from_angle(index * TAU / count + float(effect.feedback_id))
			var distance: float = radius * (0.7 + (index % 3) * 0.18)
			var tip: Vector2 = p + direction * distance
			draw_line(tip, tip - direction * (8.0 + index % 4 * 4.0) * fade, Color(color, fade * 0.8), 2.0, true)
		if age < 0.09:
			draw_circle(p, 9.0 * (1.0 - age / 0.09), Color(1, 1, 1, fade * 0.8), true, -1, true)

func _damage_shield(shield: Dictionary) -> void:
	var p: Vector2 = shield.pos
	var r: float = Core.damage_wave_radius(shield)
	var t: float = clampf(shield.age/Core.DAMAGE_WAVE_DURATION,0,1)
	var alpha: Variant = 1.0-smoothstep(.72,1.0,t)
	# Transparent interior, narrow feathered band. No screen flash, oversized
	# additive disc or second expanding radius that could imply a false hitbox.
	for layer: Variant in 4:
		var width: Variant = float(20-layer*5)
		draw_arc(p,r,0,TAU,192,Color(CYAN,alpha*(.025+layer*.018)),width,true)
	draw_arc(p,r,0,TAU,192,Color("b8fff4",alpha*.68),1.5,true)

func _bullet_cancel(remnant: Dictionary) -> void:
	var t: Variant = clampf(float(remnant.age)/Core.CANCEL_EFFECT_DURATION,0.0,1.0)
	if t >= .99: return
	var p: Vector2 = remnant.pos
	if not Rect2(Vector2(-20,-20),FIELD+Vector2(40,40)).has_point(p): return
	var r: float = remnant.radius
	var fade: Variant = (1.0-t)*(1.0-t)
	var col: Color = Color(remnant.color).lerp(Color("c0fff4"),.7)
	# The dangerous filled core/wake vanish at contact. A tiny cool glint contracts
	# immediately, then two open arcs and three short fragments dissolve in 0.5s.
	if t < .45:
		draw_circle(p,maxf(.2,r*.65*pow(1.0-t/.45,1.4)),Color(col.lightened(.4),fade*.72),true,-1,true)
	var ring_radius: Variant = r*(.85+t*.95)
	for side: Variant in 2:
		var start: float = remnant.angle+side*PI+t*.5
		draw_arc(p,ring_radius,start,start+PI*.68,12,Color(col,fade*.58),1.1,true)
	for n: Variant in 3:
		var dir: Variant = Vector2.from_angle(remnant.angle+n*TAU/3.0)
		var at: Variant = p+dir*(r+2.0+t*10.0)
		draw_line(at,at+dir*(2.0+2.0*fade),Color(col,fade*.65),1.2,true)

func _bullet_wake(b: Dictionary) -> void:
	var position_value: Vector2 = b.pos
	if not Rect2(Vector2(8, 8), FIELD - Vector2(16, 16)).has_point(position_value):
		return
	var original: Color = b.color
	var color: Color = Color("ff6096") if original.r > original.b else Color("b17bff")
	if original.g > .65 and original.r > .8:
		color = Color("ffc35e")
	if absf(float(b.angular_velocity)) > .00001:
		_curve_wake(b, Color(color, .34))
	else:
		var age: float = b.age
		var past: float = maxf(0.0, age - .36)
		var length: float = Vector2(b.vel).length() * (age - past)
		if b.has("speed_start"):
			length = Core.bullet_travel_at(b, age) - Core.bullet_travel_at(b, past)
		_trail(position_value, -Vector2(b.vel).normalized(), length, b.radius * .85, Color(color, .34))

func _bullet(b: Dictionary) -> void:
	var p: Vector2 = b.pos
	if not Rect2(Vector2(8,8),FIELD-Vector2(16,16)).has_point(p): return
	var r: float = b.get("radius",6)
	var original: Color = b.get("color",Color("ff70c8"))
	var col: Variant = Color("ff6096") if original.r>original.b else Color("b17bff")
	if original.g>.65 and original.r>.8: col=Color("ffc35e")
	var dir: Vector2 = -Vector2(b.get("vel",Vector2.DOWN)).normalized()
	var needle: bool = b.get("type","") == "needle" or b.get("kind","") == "needle"
	_soft_orb(p,r,col)
	if b.get("kind", "") == "crescent":
		# The filled disc is the collision core; this fine crescent is decoration only.
		var heading: Variant = (-dir).angle()
		_sigil_arc(p,r*1.65,heading-PI*.58,heading+PI*.58,Color(col,.65),1.1)
	if needle:
		_glyph_edge(PackedVector2Array([p+dir*r*2.4,p+dir.orthogonal()*r,p-dir*r*1.3,p-dir.orthogonal()*r]),Color(col,.85),.9)

func _curve_wake(b: Dictionary, col: Color) -> void:
	var position_value: Vector2 = b.pos
	var velocity: Vector2 = b.vel
	var curve: float = b.angular_velocity
	var duration: float = minf(float(b.age), .55)
	var radius: float = b.radius
	var straight_time: float = maxf(float(b.age) - float(b.curve_duration), 0.0)
	var base: int = curve_points.size()
	curve_points.resize(base + 39)
	curve_colors.resize(base + 39)
	# Grow shared topology only when the visible bullet count exceeds its previous peak.
	if curve_batch_indices.size() < (base / 39 + 1) * 144:
		for vertex_index: int in curve_indices:
			curve_batch_indices.append(base + vertex_index)
	# All curved wakes share one draw call, retaining the original twelve segments.
	for sample_index: int in 13:
		var progress: float = float(sample_index) / 12.0
		var back: float = duration * progress
		var past_velocity: Vector2 = velocity.rotated(-curve * maxf(back - straight_time, 0.0))
		var center: Vector2 = position_value - velocity * minf(back, straight_time) + Vector2(past_velocity.y - velocity.y, velocity.x - past_velocity.x) / curve
		var side: Vector2 = past_velocity.normalized().orthogonal() * radius * (1.0 - progress) * .85
		var index: int = base + sample_index * 3
		curve_points[index] = center
		curve_points[index + 1] = center - side
		curve_points[index + 2] = center + side
		curve_colors[index] = Color(col, col.a * pow(1.0 - progress, 1.7))
		curve_colors[index + 1] = Color(col, 0.0)
		curve_colors[index + 2] = Color(col, 0.0)

func _diamond(p: Vector2, radius: float, color: Color) -> void:
	draw_colored_polygon(_poly(p,radius,4,-PI/2),color)

func _enemy(e: Dictionary) -> void:
	var world: Vector2 = e.pos
	if not Rect2(Vector2(-150,-150),FIELD+Vector2(300,300)).has_point(world): return
	var kind: String = e.get("type","scout")
	var r: float = e.get("radius",19)
	var col: Variant = Color("ffc35e") if kind in ["gunner","sniper"] else Color("aa77ff") if kind in ["weaver","orbiter"] else Color("ff77ba")
	var squash: Vector2 = Vector2.ONE
	hit_white = 0.0
	if hit_poses.has(int(e.id)):
		var pose: Dictionary = hit_poses[int(e.id)]
		var recoil: float = sin(float(pose.age) / 0.26 * PI * 2.0) * exp(-float(pose.age) * 13.0)
		world += Vector2(pose.direction) * recoil * (2.0 if kind == "boss" else 7.0)
		squash = Vector2(1.0 + recoil * 0.16, 1.0 - recoil * 0.13)
		hit_white = maxf(0.0, 1.0 - float(pose.age) / 0.085) * 0.72
	# Rotate a fixed local-space assembly, never regenerate geometry each frame.
	# Simulation owns the angle: pause freezes it and collision remains at world.
	draw_set_transform(world, float(e.get("rotation",0.0)), squash)
	var p: Variant = Vector2.ZERO
	if kind=="boss":
		col = Color("b184ff")
		# The circle is the unchanged collision field. Everything beyond it is decoration.
		draw_set_transform(world)
		_soft_orb(p,r,Color(col,.24))
		_sigil_arc(p,r,0,TAU,Color(col.lightened(.58),.85),1.6)
		var opening: float = e.get("iris_opening",.04)
		var iris_angle: float = e.get("iris_rotation",0.0)
		var bank: float = e.get("bank",0.0)
		# Detached iris leaves move radially and hinge in delayed response to the outer blades.
		# Fixed polygons + draw transforms keep texture caching bounded throughout the motion.
		var iris_leaf: Variant = PackedVector2Array([Vector2(-6,-8),Vector2(17,-8),Vector2(27,1),Vector2(11,10),Vector2(-5,4)])
		for n: Variant in 6:
			var a: Variant = n*TAU/6.0 + iris_angle
			var pivot: Variant = Vector2.from_angle(a) * (25.0 + opening*14.0)
			draw_set_transform(world+pivot,a+.32-opening*.55)
			_soft_polygon(iris_leaf,Color(col,.60))
			draw_set_transform(world,iris_angle+bank*.4)
			_sigil_arc(p,47+opening*5,n*TAU/6.0+.08,n*TAU/6.0+.57,Color(col,.60),1.2)
		for n: Variant in 6:
			var blade_opening: float = e.get("blade_openings",PackedFloat32Array([.04,.04,.04,.04,.04,.04]))[n]
			var pose: Variant = Core.blade_transform(n,float(e.get("rotation",0.0)),blade_opening,bank)
			draw_set_transform(world+pose.origin,pose.get_rotation())
			_soft_polygon(Core.boss_blade_polygon(),col)
			# A tiny root facet is part of the energy symbol, not a bolt or a metallic linkage.
			_soft_polygon(PackedVector2Array([Vector2(-9,-4),Vector2(-4,-8),Vector2(1,-4),Vector2(-4,0)]),Color(col,.72))
		# The hub rotates at its own reduced ratio instead of being welded to all six blades.
		draw_set_transform(world,float(e.get("hub_rotation",0.0)),Vector2.ONE*(1+opening*.15))
		_soft_polygon(_poly(p,20,4,-PI/2),Color(col.lightened(.3),.9))
		_glyph_edge(PackedVector2Array([Vector2(-8,0),Vector2(0,8),Vector2(8,0),Vector2(0,-8)]),Color("f7e8ff"),1.8)
	elif kind=="sniper":
		# Long split lance and detached side glyphs, unlike the compact gunner diamond.
		for side: Variant in [-1,1]:
			_soft_polygon(PackedVector2Array([Vector2(side*4,-r*1.2),Vector2(side*r*.65,0),Vector2(side*4,r*1.35),Vector2(side*9,0)]),col)
			_glyph_edge(PackedVector2Array([Vector2(side*r*.9,-r*.4),Vector2(side*r*1.15,0),Vector2(side*r*.9,r*.4)]),col.lightened(.5),1.5,false)
		_soft_orb(p,4,col)
	elif kind=="sweeper":
		# Wide detached scythes advertise lateral motion.
		for side: Variant in [-1,1]:
			_soft_polygon(PackedVector2Array([Vector2(side*5,-r*.35),Vector2(side*r*1.5,-r*.65),Vector2(side*r*1.1,r*.5),Vector2(side*r*.7,0)]),col)
		_glyph_edge(_poly(p,7,4,PI*.5),col.lightened(.65),1.7)
	elif kind=="orbiter":
		# Broken circular gate: a persistent enemy silhouette, not an attack cue.
		for n: Variant in range(3):
			var a: Variant = n*TAU/3.0-PI*.5
			_sigil_arc(p,r,a+.15,a+1.65,col.lightened(.45),2)
			_soft_polygon(_poly(Vector2.from_angle(a)*r,6,3,a),col)
		_glyph_edge(_poly(p,r*.45,6,0),col,1.3)
	elif kind=="gunner":
		_soft_polygon(_poly(p,r,4,PI/2),col)
		for n: Variant in range(3):
			var a: Variant = n*TAU/3+PI/2
			_sigil_arc(p,r*1.2,a-.32,a+.32,col.lightened(.45),1.5)
		_glyph_edge(_poly(p,r*.39,3,PI/2),col.lightened(.7),1.4)
	elif kind=="weaver":
		for side: Variant in [-1,1]:
			_soft_polygon(PackedVector2Array([p+Vector2(0,-r),p+Vector2(side*r*1.2,0),p+Vector2(side*r*.48,r*.7),p+Vector2(side*r*.6,0)]),col)
		_glyph_edge(_poly(p,5,4,0),col.lightened(.65),1.5)
	else:
		_soft_polygon(PackedVector2Array([p+Vector2(-r,-r*.6),p+Vector2(0,r*1.3),p+Vector2(r,-r*.6),p+Vector2(0,-r*.2)]),col)
		_glyph_edge(PackedVector2Array([p+Vector2(-r*.36,0),p+Vector2(0,r*.5),p+Vector2(r*.36,0)]),col.lightened(.65),1.3,false)
	hit_white = 0.0
	draw_set_transform(ORIGIN)

func _player(color: Color) -> void:
	var p: Vector2 = core.player
	if core.state=="lost": return
	var alpha: Variant = .45 if core.invulnerable>0 and sin(visual_time*25)>0 else 1.0
	for side: Variant in [-1,1]:
		_ribbon(p+Vector2(side*10,12),Vector2.DOWN,65,9,Color(color,alpha*.32),side*.8)
		var wing: Variant = PackedVector2Array([p+Vector2(side*4,-13),p+Vector2(side*25,17),p+Vector2(side*7,8),p+Vector2(side*3,17)])
		_soft_polygon(wing,Color(color,alpha))
	_soft_polygon(PackedVector2Array([p+Vector2(0,-27),p+Vector2(5,-5),p+Vector2(0,5),p+Vector2(-5,-5)]),Color(color.lightened(.6),alpha))
	if core.focused: _soft_orb(p,4,Color("ffffff"))

func _hud() -> void:
	# Small translucent edge overlays; the playfield continues behind them.
	_hud_strip(Rect2(20, 18, 254, 44),CYAN)
	_text(Vector2(36, 47), "分数  %08d" % core.score, 22, Color("effaf5"))
	_hud_strip(Rect2(FIELD.x - 360, 18, 280, 44),Color("b184ff"))
	_diamond(Vector2(FIELD.x - 337, 40), 7, CYAN)
	_text(Vector2(FIELD.x - 320, 47), "生命 %d" % core.lives, 20, Color("effaf5"))
	draw_arc(Vector2(FIELD.x - 213, 40), 7, 0, TAU, 24, GOLD, 2)
	_text(Vector2(FIELD.x - 197, 47), "脉冲 %d" % core.bombs, 20, GOLD)
	_hud_strip(Rect2(FIELD.x - 64, 18, 44, 44),CYAN)
	for x: Variant in [FIELD.x - 47, FIELD.x - 37]:
		draw_line(Vector2(x, 32), Vector2(x, 48), Color("c1d7df"), 3)
	if not core.boss.is_empty():
		var bar_width: Variant = minf(460, FIELD.x * 0.34)
		var left: Variant = (FIELD.x - bar_width) * 0.5
		_hud_strip(Rect2(left - 12, 10, bar_width + 24, 46),Color("b184ff"))
		_center(Vector2(FIELD.x * 0.5, 32), "HARBINGER  /  %d" % core.boss.phase, 15, Color("e6cafa"))
		draw_rect(Rect2(left, 43, bar_width, 4), Color("3c304f"))
		draw_rect(Rect2(left, 43, bar_width * clampf(float(core.boss.hp) / core.boss.max_hp, 0, 1), 4), Color("c780ff"))

func _hud_style() -> StyleBoxFlat:
	var style: Variant = StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.045, 0.09, 0.72)
	style.set_corner_radius_all(3)
	return style

func _overlay() -> void:
	draw_rect(Rect2(Vector2.ZERO, FIELD),Color(0.025,0.04,0.1,0.88))
	draw_set_transform(FIELD * 0.5 - Vector2(720, 480))
	var title: Variant = "星 潮"
	var sub: Variant = "S T A R F A L L"
	var body: Variant = "一架战机，一道防线。"
	var action: Variant = "开始出击  /  ENTER"
	if paused:
		title = "航行暂停"; sub = "F L I G H T   P A U S E D"; body = "按 Enter / Esc 继续，按 R 重新出击。"; action = "继续航行  /  ENTER"
	elif core.state == "won":
		title = "防线守住了"; sub = "M I S S I O N   C L E A R"; body = "最终得分  %08d" % core.score; action = "再次出击  /  ENTER"
	elif core.state == "lost":
		title = "信号中断"; sub = "S I G N A L   L O S T"; body = "最终得分  %08d  ·  再试一次。" % core.score; action = "重新出击  /  ENTER"
	_soft_polygon(_poly(Vector2(720,260),48,6,PI/6),Color("64d2d9"))
	_soft_orb(Vector2(720,260),12,GOLD)
	_center(Vector2(720,375),title,53,Color("f3f2df"))
	_center(Vector2(720,420),sub,20,CYAN)
	_center(Vector2(720,490),body,19,Color("b9ccdf"))
	if core.state == "ready":
		_center(Vector2(720,529),"自动连射已开启。按住 Shift 穿越弹幕。",17,Color("b9ccdf"))
	draw_rect(Rect2(520,585,400,62),CYAN)
	_center(Vector2(720,625),action,23,INK)
	_center(Vector2(720,708),"移动  WASD    ·    精确移动  SHIFT    ·    消弹  X",15,Color("a2b6ce"))

func _make_sound(kind: String) -> AudioStreamWAV:
	var wav: Variant = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	var duration: float = 0.07 if kind == "hit" else 0.42 if kind in ["bomb", "break", "phase"] else 0.22
	var count: Variant = int(duration * wav.mix_rate)
	var bytes: Variant = PackedByteArray()
	bytes.resize(count*2)
	for i: Variant in range(count):
		var t: Variant = float(i)/wav.mix_rate
		var freq: Variant = 240.0 + t*1200 if kind == "start" or kind == "clear" else 130.0 - t*90
		if kind == "hit":
			freq = 850.0 - t * 7000.0
		elif kind == "break":
			freq = 180.0 - t * 250.0
		elif kind == "phase":
			freq = 90.0 + t * 450.0
		var grain: float = sin(i * 78.233) * sin(i * 12.9898) if kind in ["hit", "break"] else 0.0
		var value: float = (sin(TAU * freq * t) * 0.3 + grain * 0.15) * pow(1.0 - float(i) / count, 2)
		bytes.encode_s16(i*2,int(value*32767))
	wav.data = bytes
	return wav

func _play(kind: String) -> void:
	if muted or audio == null: return
	audio.stream = sounds[kind]
	audio.play()

func _field_arc(p: Vector2, radius: float, color: Color, width: float) -> void:
	var bounds: Variant = Rect2(Vector2(2,2),FIELD - Vector2(4,4))
	for i: Variant in range(100):
		var a: Variant = p + Vector2.from_angle(i*TAU/100)*radius
		var b: Variant = p + Vector2.from_angle((i+1)*TAU/100)*radius
		if bounds.has_point(a) and bounds.has_point(b): draw_line(a,b,color,width,true)

## The narrow shot glyph and its bright rim share a fixed mesh, including all outlines.
func _setup_shot_heads() -> void:
	var points: PackedVector2Array = PackedVector2Array([Vector2(0, -12), Vector2(3, 0), Vector2(0, 7), Vector2(-3, 0)])
	var vertices: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array([4, 5, 6, 4, 6, 7])
	for layer: int in 2:
		for point: Vector2 in points:
			vertices.append(Vector3(point.x, point.y, 0) * (1.0 if layer == 0 else 0.82))
			colors.append(Color("efffff") if layer == 0 else Color("c5fff8"))
	for edge: int in 4:
		var next: int = (edge + 1) % 4
		indices.append_array(PackedInt32Array([edge, next, next + 4, edge, next + 4, edge + 4]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	shot_heads = MultiMesh.new()
	shot_heads.transform_format = MultiMesh.TRANSFORM_2D
	shot_heads.mesh = mesh
	shot_heads.instance_count = Core.MAX_SHOTS * 8
	shot_heads.visible_instance_count = 0
	shot_heads.custom_aabb = AABB(Vector3(-20, -20, -1), Vector3(1480, 1000, 2))
	var canvas: MultiMeshInstance2D = MultiMeshInstance2D.new()
	canvas.multimesh = shot_heads
	canvas.z_index = -1
	add_child(canvas)

## Build the four feathered strips once; the GPU bends each instance independently.
func _setup_ribbons() -> void:
	var vertices: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	for layer: int in 2:
		for side: float in [-1.0, 1.0]:
			var base: int = vertices.size()
			for sample_index: int in 13:
				var progress: float = float(sample_index) / 12.0
				var center: float = layer * 0.35 * progress
				var edge: float = center + side * (1.0 - progress) * (0.82 if layer == 0 else 0.38)
				vertices.append(Vector3(center, progress, 0))
				vertices.append(Vector3(edge, progress, 0))
				uvs.append(Vector2(0, progress))
				uvs.append(Vector2(1, progress))
				colors.append(Color(1, 1, 1, pow(1.0 - progress, 1.4) * (0.8 if layer == 0 else 0.48)))
				colors.append(Color(1, 1, 1, 0))
			for segment: int in 12:
				var index: int = base + segment * 2
				indices.append_array(PackedInt32Array([index, index + 2, index + 3, index, index + 3, index + 1]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	ribbons = MultiMesh.new()
	ribbons.transform_format = MultiMesh.TRANSFORM_2D
	ribbons.use_colors = true
	ribbons.use_custom_data = true
	ribbons.mesh = mesh
	ribbons.instance_count = Core.MAX_SHOTS * 8 + 16
	ribbons.visible_instance_count = 0
	ribbons.custom_aabb = AABB(Vector3(-160, -160, -1), Vector3(1760, 1280, 2))
	var canvas: MultiMeshInstance2D = MultiMeshInstance2D.new()
	canvas.multimesh = ribbons
	canvas.z_index = -1
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = preload("res://games/minigame/godot_party_default_star_wave/assets/shaders/ribbon.gdshader")
	canvas.material = material
	add_child(canvas)

func _ribbon(p: Vector2, dir: Vector2, length: float, width: float, col: Color, curl: float = 1.0) -> void:
	ribbons.set_instance_transform_2d(ribbon_count, Transform2D(dir.orthogonal() * width, dir * length, p))
	ribbons.set_instance_color(ribbon_count, col)
	ribbons.set_instance_custom_data(ribbon_count, Color(curl, 0, 0, 0))
	ribbon_count += 1

func _glyph_edge(pts: PackedVector2Array, col: Color, width: float = 1.3, closed: bool = true) -> void:
	draw_polyline(pts+PackedVector2Array([pts[0]]) if closed else pts,col,width,true)

func _sigil_arc(p: Vector2, radius: float, start: float, end: float, col: Color, width: float) -> void:
	draw_arc(p,radius,start,end,64,col,width,true)

func _hud_strip(rect: Rect2, col: Color) -> void:
	var a: Variant = rect.position
	var b: Variant = rect.end
	draw_polygon(PackedVector2Array([a,Vector2(b.x,a.y),b,Vector2(a.x,b.y)]),PackedColorArray([Color(col,.18),Color(col,0),Color(col,0),Color(col,.07)]))
	draw_line(a,Vector2(a.x,b.y),Color(col.lightened(.45),.9),1.5,true)
	draw_line(Vector2(a.x,b.y),Vector2(b.x,b.y),Color(col,.22),.8,true)
