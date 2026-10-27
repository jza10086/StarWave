extends Node2D

const Core = preload("res://scripts/game_core.gd")
const FONT = preload("res://assets/fonts/NotoSansSC-Regular.otf")
const ORIGIN = Vector2.ZERO
var FIELD := Vector2(1440, 960)
const CYAN = Color("62ebda")
const GOLD = Color("f4d88f")
const INK = Color("050718")
var core = Core.new()
var paused := false
var auto_fire := true
var motion := true
var muted := false
var visual_time := 0.0
var bomb_flash := 0.0
var last_lives := 3
var last_score := 0
var sounds: Dictionary = {}
var audio: AudioStreamPlayer
var pointer_active := false
var shape_cache: Dictionary = {}
var aura: ImageTexture
var beam: ImageTexture
var energy_ring: ImageTexture
var light_canvas: Node2D
var space_canvas: ColorRect

# Generated once. Gaussian alpha is continuous, not concentric solid bands.
func _make_light_texture(kind: int) -> ImageTexture:
	var size = Vector2i(128, 128) if kind != 1 else Vector2i(128, 32)
	var img = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in range(size.y):
		for x in range(size.x):
			var uv = Vector2((x+.5)/size.x, (y+.5)/size.y) * 2.0 - Vector2.ONE
			var r = uv.length()
			var alpha = exp(-r*r*5.5) * (1.0-smoothstep(.75,1.0,r))
			if kind == 1: alpha = exp(-uv.y*uv.y*6.0) * (1.0-smoothstep(.7,1.0,absf(uv.y))) * (1.0-smoothstep(.75,1.0,absf(uv.x)))
			if kind == 2: alpha = exp(-pow((r-.72)/.065,2)) * (1.0-smoothstep(.95,1.0,r))
			img.set_pixel(x,y,Color(1,1,1,alpha))
	return ImageTexture.create_from_image(img)

func _setup_lighting() -> void:
	aura = _make_light_texture(0)
	beam = _make_light_texture(1)
	energy_ring = _make_light_texture(2)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	space_canvas = ColorRect.new()
	space_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	space_canvas.z_index = -2
	var space_material = ShaderMaterial.new()
	space_material.shader = preload("res://assets/shaders/deep_space.gdshader")
	space_canvas.material = space_material
	add_child(space_canvas)
	light_canvas = Node2D.new()
	light_canvas.z_index = -1
	var light_material = CanvasItemMaterial.new()
	light_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	light_canvas.material = light_material
	light_canvas.draw.connect(_light_pass)
	add_child(light_canvas)

func _aura_at(p: Vector2, radius: Vector2, col: Color) -> void:
	light_canvas.draw_texture_rect(aura,Rect2(p-radius,radius*2),false,col)

func _light_pass() -> void:
	for e in core.enemies:
		var col = Color("eeb66c") if e.type=="gunner" else Color("af88e7") if e.type=="weaver" else Color("e67eaa")
		_aura_at(e.pos,Vector2.ONE*e.radius*3.4,Color(col,.12))
	if not core.boss.is_empty():
		var p: Vector2 = core.boss.pos
		_aura_at(p,Vector2(220,160),Color(.47,.24,1,.24))
	for shot in core.shots: _aura_at(shot.pos,Vector2(13,30),Color(CYAN,.27))
	for b in core.bullets:
		var original: Color = b.get("color",Color("ff70c8"))
		var col = Color("e67eaa") if original.r>original.b else Color("bc85f5")
		if original.g>.65 and original.r>.8: col=Color("ffc16a")
		_aura_at(b.pos,Vector2.ONE*b.get("radius",6)*3.4,Color(col,.09))
	for pick in core.pickups: _aura_at(pick.pos,Vector2(42,42),Color(GOLD,.24))
	if core.state!="lost":
		_aura_at(core.player,Vector2(65,65),Color(CYAN,.18))
		_aura_at(core.player+Vector2(0,34),Vector2(40,70),Color(.15,.45,1,.22))
	for effect in core.effects:
		var a = clampf(1.0-effect.get("age",0)/maxf(effect.get("life",.5),.001),0,1)
		_aura_at(effect.pos,Vector2.ONE*effect.get("radius",24)*3,Color(CYAN,a*.28))


func _ready() -> void:
	_setup_lighting()
	core.reset()
	get_viewport().size_changed.connect(_resize_field)
	_resize_field()
	audio = AudioStreamPlayer.new()
	audio.volume_db = -18
	add_child(audio)
	for kind in ["start", "bomb", "hurt", "clear"]:
		sounds[kind] = _make_sound(kind)
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if core != null and core.state == "playing":
			paused = true
		pointer_active = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ENTER:
				if core.state != "playing": _start()
				elif paused: paused = false
			KEY_ESCAPE, KEY_P:
				if core.state == "playing": paused = not paused
			KEY_R:
				if core.state != "playing" or paused: _start()
			KEY_F: auto_fire = not auto_fire
			KEY_M: muted = not muted
			KEY_V: motion = not motion
			KEY_X, KEY_SPACE:
				if core.state == "playing" and not paused and core.bombs > 0:
					core.step(0.0, Vector2.ZERO, false, false, true)
					bomb_flash = 0.65
					_play("bomb")
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var p = get_global_mouse_position()
		if core.state != "playing" or paused:
			if Rect2(FIELD * 0.5 + Vector2(-200, 105), Vector2(400, 62)).has_point(p):
				if paused: paused = false
				else: _start()
		elif Rect2(FIELD.x - 64, 16, 48, 44).has_point(p):
			paused = true

func _start() -> void:
	core.start()
	paused = false
	bomb_flash = 0.0
	last_lives = core.lives
	last_score = 0
	_play("start")

func _process(delta: float) -> void:
	var dt = minf(delta, 0.05)
	if not paused:
		visual_time += dt
		bomb_flash = maxf(0, bomb_flash - dt)
	if core.state == "playing" and not paused:
		var move = Vector2(float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)), float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)))
		core.step(dt, move.limit_length(), auto_fire or Input.is_key_pressed(KEY_Z), Input.is_key_pressed(KEY_SHIFT), false)
		if core.lives < last_lives:
			_play("hurt")
			last_lives = core.lives
		if core.state == "won": _play("clear")
	queue_redraw()

func _draw() -> void:
	_background()
	light_canvas.queue_redraw()
	draw_set_transform(ORIGIN)
	_field()
	draw_set_transform(Vector2.ZERO)
	if core.state == "playing" and not paused: _hud()
	if core.state != "playing" or paused: _overlay()

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
	var dir = (b-a).normalized()
	var side = dir.orthogonal()*(width+12)*.5
	var pts = PackedVector2Array([a-dir*5-side,b+dir*5-side,b+dir*5+side,a-dir*5+side])
	draw_polygon(pts,PackedColorArray([Color(color,color.a*.38)]),PackedVector2Array([Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]),beam)
	draw_line(a,b,color,width,true)

func _poly(p: Vector2, radius: float, sides: int, angle: float = 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(sides): pts.append(p + Vector2.from_angle(angle + TAU*i/sides)*radius)
	return pts

# Transparent colored planes and alpha falloff, rasterized at 4x. No black contours.
# Keys are local geometry + palette only: movement never allocates textures.
func _bleed_transparent_rgb(img: Image, col: Color) -> void:
	# Transparent black leaks into RGB mip averages unless the entire padding is filled.
	for y in img.get_height():
		var edge_color = col.lightened(.15).lerp(col.darkened(.18),float(y)/img.get_height())
		for x in img.get_width():
			if img.get_pixel(x,y).a == 0.0:
				img.set_pixel(x,y,Color(edge_color,0))

func _soft_polygon(pts: PackedVector2Array, col: Color) -> void:
	var bounds = Rect2(pts[0],Vector2.ZERO)
	for pt in pts: bounds = bounds.expand(pt)
	var points := ""
	for pt in pts:
		var local = pt-bounds.position+Vector2.ONE*2
		points += "%.2f,%.2f " % [local.x,local.y]
	var key = points+col.to_html(false)
	if not shape_cache.has(key):
		var size = bounds.size+Vector2.ONE*4
		# Explicit pixel-space coordinates avoid renderer-dependent objectBoundingBox units.
		# Frame stays inside the original silhouette: clip the wide colored stroke.
		var svg = '<svg xmlns="http://www.w3.org/2000/svg" width="%s" height="%s"><defs><linearGradient id="v" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="%s" y2="%s"><stop stop-color="#%s" stop-opacity="0.38"/><stop offset="0.55" stop-color="#%s" stop-opacity="0.18"/><stop offset="1" stop-color="#%s" stop-opacity="0.05"/></linearGradient><clipPath id="shape"><polygon points="%s"/></clipPath></defs><polygon points="%s" fill="url(#v)"/><polygon points="%s" fill="none" stroke="#%s" stroke-opacity="0.95" stroke-width="2.6" stroke-linejoin="round" clip-path="url(#shape)"/></svg>' % [size.x,size.y,size.x*.35,size.y,col.to_html(false),col.to_html(false),col.to_html(false),points,points,points,col.lightened(.56).to_html(false)]
		var img = Image.new()
		img.load_svg_from_string(svg,4.0)
		_bleed_transparent_rgb(img,col)
		img.generate_mipmaps()
		shape_cache[key] = ImageTexture.create_from_image(img)
	draw_texture_rect(shape_cache[key],Rect2(bounds.position-Vector2.ONE*2,bounds.size+Vector2.ONE*4),false,Color(1,1,1,col.a))

func _soft_orb(p: Vector2, r: float, col: Color) -> void:
	var key = "orb"+col.to_html(false)
	if not shape_cache.has(key):
		# Flat colored energy disc with luminous circumference; no sphere lighting or specular spot.
		var svg = '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><circle cx="32" cy="32" r="30" fill="#%s" fill-opacity="0.68"/><circle cx="32" cy="32" r="27.8" fill="none" stroke="#%s" stroke-width="4.4"/></svg>' % [col.to_html(false),col.lightened(.65).to_html(false)]
		var img = Image.new()
		img.load_svg_from_string(svg,4.0)
		_bleed_transparent_rgb(img,col)
		img.generate_mipmaps()
		shape_cache[key] = ImageTexture.create_from_image(img)
	var extent = r*32.0/30.0
	draw_texture_rect(shape_cache[key],Rect2(p-Vector2.ONE*extent,Vector2.ONE*extent*2),false,Color(1,1,1,col.a))

func _neon_ring(p: Vector2, radius: float, color: Color, width: float = 1.5, start: float = 0, end: float = TAU) -> void:
	# Annular Gaussian is used for full energy rings; arcs remain fine, clean cores.
	if end-start >= TAU-.01 and radius>8:
		var extent = radius/.72
		draw_texture_rect(energy_ring,Rect2(p-Vector2.ONE*extent,Vector2.ONE*extent*2),false,Color(color,color.a*.34))
	draw_arc(p,radius,start,end,96,color,width,true)

func _space() -> void:
	var t = visual_time if motion else 0.0
	# Small continuous light discs, never single-pixel squares or wire fragments.
	for i in range(int(FIELD.x*FIELD.y/14000)):
		var pos = Vector2(fmod(i*137.71,FIELD.x-14)+7,fmod(i*73.31+t*(5+i%4*3),FIELD.y-4)+2)
		draw_texture_rect(aura,Rect2(pos-Vector2.ONE*2.5,Vector2.ONE*5),false,Color(.68,.73,.88,.22+float(i%3)*.08))

func _field() -> void:
	_space()
	for shot in core.shots:
		var p: Vector2 = shot.pos
		if not Rect2(Vector2(5,0),FIELD-Vector2(10,0)).has_point(p): continue
		_ribbon(p+Vector2(0,4),Vector2.DOWN,80,8,Color(CYAN,.42),sin(p.x*.07))
		# White-cyan sliver glyph: the same narrow shot center, not a bead or a laser rod.
		var head = PackedVector2Array([p+Vector2(0,-12),p+Vector2(3,0),p+Vector2(0,7),p+Vector2(-3,0)])
		draw_colored_polygon(head,Color("c5fff8"))
		_glyph_edge(head,Color("efffff"),.7)

	for e in core.enemies: _enemy(e)
	if not core.boss.is_empty(): _enemy(core.boss)
	for pick in core.pickups:
		var p: Vector2 = pick.pos
		_soft_polygon(_poly(p,17,4,-PI/2),GOLD)
		_center(p+Vector2(0,5),"P" if pick.get("type","power")=="power" else "B",14,Color("fff1ce"))
	for effect in core.effects: _impact(effect)
	for b in core.bullets: _bullet(b)
	_player()
	if bomb_flash > 0:
		draw_rect(Rect2(Vector2.ZERO,FIELD),Color(.3,1,.93,bomb_flash*.10))
		_neon_ring(core.player,maxf(0,(.65-bomb_flash)*1600),Color(CYAN,bomb_flash*.85),2)

func _trail(p: Vector2, dir: Vector2, length: float, width: float, col: Color) -> void:
	var side = dir.orthogonal()
	for i in range(8):
		var t0 = float(i)/8
		var t1 = float(i+1)/8
		for sign_side in [-1,1]:
			var a = p+dir*length*t0
			var b = p+dir*length*t1
			var pts = PackedVector2Array([a,b,b+side*sign_side*width*(1-t1),a+side*sign_side*width*(1-t0)])
			draw_polygon(pts,PackedColorArray([Color(col,col.a*pow(1-t0,1.7)),Color(col,col.a*pow(1-t1,1.7)),Color(col,0),Color(col,0)]))

func _impact(effect: Dictionary) -> void:
	var age: float = effect.get("age",0)
	var life: float = maxf(effect.get("life",.5),.001)
	var a = clampf(1-age/life,0,1)
	var p: Vector2 = effect.pos
	var r: float = effect.get("radius",24)*(1+age*3)
	# Hollow, fading fragments never resemble filled hostile bullet cores.
	_neon_ring(p,r,Color(CYAN,a*.6),1.2)
	_neon_ring(p,r*.72,Color(.62,.5,1,a*.24),.8)
	for n in range(7):
		var dir = Vector2.from_angle(n*TAU/7+float(effect.get("radius",24)))
		var q = p+dir*r*(.65+float(n%3)*.2)
		var pts = PackedVector2Array([q+dir*(8+n%3*3)*a,q+dir.orthogonal()*4*a,q-dir*(4+n%2*3)*a])
		if Rect2(Vector2(8,8),FIELD-Vector2(16,16)).has_point(q):
			draw_colored_polygon(pts,Color(.38,.68,1,a*.10))
			draw_polyline(pts+PackedVector2Array([pts[0]]),Color(.55,.82,1,a*.65),1,true)
	if age<.12: _neon_ring(p,5+age*80,Color(.8,1,1,a*.65),2)

func _bullet(b: Dictionary) -> void:
	var p: Vector2 = b.pos
	if not Rect2(Vector2(8,8),FIELD-Vector2(16,16)).has_point(p): return
	var r: float = b.get("radius",6)
	var original: Color = b.get("color",Color("ff70c8"))
	var col = Color("ff6096") if original.r>original.b else Color("b17bff")
	if original.g>.65 and original.r>.8: col=Color("ffc35e")
	var dir: Vector2 = -Vector2(b.get("vel",Vector2.DOWN)).normalized()
	var needle: bool = b.get("type","") == "needle" or b.get("kind","") == "needle"
	# Curved Boss wakes reconstruct actual recent arc positions, without history buffers.
	if absf(float(b.get("angular_velocity",0.0))) > .00001:
		_curve_wake(b,Color(col,.34))
	else:
		_ribbon(p,dir,66.0 if needle else 44.0,r*1.65,Color(col,.34),-1.0 if col.g>.5 else 1.0)
	_soft_orb(p,r,col)
	if needle:
		_glyph_edge(PackedVector2Array([p+dir*r*2.4,p+dir.orthogonal()*r,p-dir*r*1.3,p-dir.orthogonal()*r]),Color(col,.85),.9)

func _curve_wake(b: Dictionary, col: Color) -> void:
	var p: Vector2 = b.pos
	var velocity: Vector2 = b.vel
	var curve: float = b.angular_velocity
	var duration: float = minf(float(b.age),.55)
	var r: float = b.radius
	# Twelve bounded segments with transparent outer edges; exact inverse of the core's circular-arc integration.
	for n in range(12):
		var t0 := float(n)/12.0
		var t1 := float(n+1)/12.0
		var straight_time := maxf(float(b.age)-float(b.get("curve_duration",3.0)),0.0)
		var back0 := duration*t0
		var back1 := duration*t1
		var v0 := velocity.rotated(-curve*maxf(back0-straight_time,0.0))
		var v1 := velocity.rotated(-curve*maxf(back1-straight_time,0.0))
		var a := p-velocity*minf(back0,straight_time)+Vector2(v0.y-velocity.y,velocity.x-v0.x)/curve
		var bpos := p-velocity*minf(back1,straight_time)+Vector2(v1.y-velocity.y,velocity.x-v1.x)/curve
		var side0 := v0.normalized().orthogonal()*r*(1-t0)*.85
		var side1 := v1.normalized().orthogonal()*r*(1-t1)*.85
		# Two feathered halves retain the approved soft colored ribbon, never a hard wedge.
		for sign_side in [-1,1]:
			draw_polygon(PackedVector2Array([a,bpos,bpos+side1*sign_side,a+side0*sign_side]),PackedColorArray([Color(col,col.a*pow(1-t0,1.7)),Color(col,col.a*pow(1-t1,1.7)),Color(col,0),Color(col,0)]))

func _diamond(p: Vector2, radius: float, color: Color) -> void:
	draw_colored_polygon(_poly(p,radius,4,-PI/2),color)

func _attack_cue(e: Dictionary, p: Vector2, col: Color) -> void:
	var remaining: float = e.get("attack_telegraph", e.get("telegraph", 0.0))
	if remaining <= 0.0: return
	var angle: float = e.get("warning_angle", PI*.5)
	var kind: String = e.get("type", "")
	if kind in ["orbiter","sweeper"] or (kind == "boss" and int(e.get("choreography_slot", 0)) >= 4):
		# Open sector is deliberately hollow; short brackets mark its safe opening.
		angle = e.get("gap_angle", angle)
		for side in [-1, 1]:
			var direction = Vector2.from_angle(angle + side*(.20 if kind == "sweeper" else .34))
			draw_line(p+direction*40, p+direction*110, Color(col,.45), 1.2, true)
	else:
		var direction = Vector2.from_angle(angle)
		var origins: Array[Vector2] = [p]
		if kind == "boss":
			origins = [p+Core.blade_tip_offset(0,float(e.get("rotation",0.0))),p+Core.blade_tip_offset(1,float(e.get("rotation",0.0)))]
		for origin in origins:
			for n in range(9):
				var distance := 36.0 + n*28.0
				draw_line(origin+direction*distance, origin+direction*(distance+12),Color(col,.38),1.2,true)
	_sigil_arc(p, float(e.get("radius", 24))+9, -PI*.5, -PI*.5+TAU*clampf(remaining/.8,0,1),Color(col,.65),1.3)

func _enemy(e: Dictionary) -> void:
	var world: Vector2 = e.pos
	if not Rect2(Vector2(-150,-150),FIELD+Vector2(300,300)).has_point(world): return
	var kind: String = e.get("type","scout")
	var r: float = e.get("radius",19)
	var col = Color("ffc35e") if kind in ["gunner","sniper"] else Color("aa77ff") if kind in ["weaver","orbiter"] else Color("ff77ba")
	if float(e.get("flash",0))>0: col=col.lightened(.35)
	_attack_cue(e,world,col)
	# Rotate a fixed local-space assembly, never regenerate geometry each frame.
	# Simulation owns the angle: pause freezes it and collision remains at world.
	draw_set_transform(world, float(e.get("rotation",0.0)) if kind=="boss" else 0.0)
	var p := Vector2.ZERO
	if kind=="boss":
		col=Color("b184ff") if float(e.get("flash",0))<=0 else Color("e6bfff")
		_soft_orb(p,r,Color(col,.32))
		_sigil_arc(p,r,0,TAU,Color(col.lightened(.58),.9),1.8)
		for n in range(6):
			var a = float(n)*TAU/6-PI/2
			_sigil_arc(p,r*.78,a+.10,a+.72,Color(col,.9),2.0)
			_sigil_arc(p,r*1.12,a+.13,a+.72,Color(col,.55),.9)
			var axis = Vector2.from_angle(a)
			var tangent = axis.orthogonal()
			var blade = PackedVector2Array([p+axis*r*.98+tangent*8,p+Core.blade_tip_offset(n,0.0),p+axis*r*1.43+tangent*5,p+axis*r*1.13-tangent*8])
			_soft_polygon(blade,col)
			_ribbon(p+axis*r*1.45+tangent*9,-tangent,40,8,Color(col,.13),1.0)
		_soft_polygon(_poly(p,24,4,-PI/2),Color(col.lightened(.3),.9))
		_glyph_edge(PackedVector2Array([p+Vector2(-9,0),p+Vector2(0,10),p+Vector2(9,0),p+Vector2(0,-10)]),Color("f7e8ff"),2.2)
	elif kind=="sniper":
		# Long split lance and targeting brackets, unlike the compact gunner diamond.
		for side in [-1,1]:
			_soft_polygon(PackedVector2Array([Vector2(side*4,-r*1.2),Vector2(side*r*.65,0),Vector2(side*4,r*1.35),Vector2(side*9,0)]),col)
			_glyph_edge(PackedVector2Array([Vector2(side*r*.9,-r*.4),Vector2(side*r*1.15,0),Vector2(side*r*.9,r*.4)]),col.lightened(.5),1.5,false)
		_soft_orb(p,4,col)
	elif kind=="sweeper":
		# Wide detached scythes advertise lateral motion.
		for side in [-1,1]:
			_soft_polygon(PackedVector2Array([Vector2(side*5,-r*.35),Vector2(side*r*1.5,-r*.65),Vector2(side*r*1.1,r*.5),Vector2(side*r*.7,0)]),col)
		_glyph_edge(_poly(p,7,4,PI*.5),col.lightened(.65),1.7)
	elif kind=="orbiter":
		# Broken circular gate: recognizable even without its warning cue.
		for n in range(3):
			var a := n*TAU/3.0-PI*.5
			_sigil_arc(p,r,a+.15,a+1.65,col.lightened(.45),2)
			_soft_polygon(_poly(Vector2.from_angle(a)*r,6,3,a),col)
		_glyph_edge(_poly(p,r*.45,6,0),col,1.3)
	elif kind=="gunner":
		_soft_polygon(_poly(p,r,4,PI/2),col)
		for n in range(3):
			var a = n*TAU/3+PI/2
			_sigil_arc(p,r*1.2,a-.32,a+.32,col.lightened(.45),1.5)
		_glyph_edge(_poly(p,r*.39,3,PI/2),col.lightened(.7),1.4)
	elif kind=="weaver":
		for side in [-1,1]:
			_soft_polygon(PackedVector2Array([p+Vector2(0,-r),p+Vector2(side*r*1.2,0),p+Vector2(side*r*.48,r*.7),p+Vector2(side*r*.6,0)]),col)
		_glyph_edge(_poly(p,5,4,0),col.lightened(.65),1.5)
	else:
		_soft_polygon(PackedVector2Array([p+Vector2(-r,-r*.6),p+Vector2(0,r*1.3),p+Vector2(r,-r*.6),p+Vector2(0,-r*.2)]),col)
		_glyph_edge(PackedVector2Array([p+Vector2(-r*.36,0),p+Vector2(0,r*.5),p+Vector2(r*.36,0)]),col.lightened(.65),1.3,false)
	draw_set_transform(ORIGIN)

func _player() -> void:
	var p: Vector2 = core.player
	if core.state=="lost": return
	var alpha = .45 if core.invulnerable>0 and sin(visual_time*25)>0 else 1.0
	for side in [-1,1]:
		_ribbon(p+Vector2(side*10,12),Vector2.DOWN,65,9,Color(CYAN,alpha*.32),side*.8)
		var wing = PackedVector2Array([p+Vector2(side*4,-13),p+Vector2(side*25,17),p+Vector2(side*7,8),p+Vector2(side*3,17)])
		_soft_polygon(wing,Color(CYAN,alpha))
	_soft_polygon(PackedVector2Array([p+Vector2(0,-27),p+Vector2(5,-5),p+Vector2(0,5),p+Vector2(-5,-5)]),Color(CYAN.lightened(.6),alpha))
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
	for x in [FIELD.x - 47, FIELD.x - 37]:
		draw_line(Vector2(x, 32), Vector2(x, 48), Color("c1d7df"), 3)
	if not core.boss.is_empty():
		var bar_width = minf(460, FIELD.x * 0.34)
		var left = (FIELD.x - bar_width) * 0.5
		_hud_strip(Rect2(left - 12, 10, bar_width + 24, 46),Color("b184ff"))
		_center(Vector2(FIELD.x * 0.5, 32), "HARBINGER  /  %d" % core.boss.phase, 15, Color("e6cafa"))
		draw_rect(Rect2(left, 43, bar_width, 4), Color("3c304f"))
		draw_rect(Rect2(left, 43, bar_width * clampf(float(core.boss.hp) / core.boss.max_hp, 0, 1), 4), Color("c780ff"))

func _hud_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.045, 0.09, 0.72)
	style.set_corner_radius_all(3)
	return style

func _overlay() -> void:
	draw_rect(Rect2(Vector2.ZERO, FIELD),Color(0.025,0.04,0.1,0.88))
	draw_set_transform(FIELD * 0.5 - Vector2(720, 480))
	var title = "星 潮"
	var sub = "S T A R F A L L"
	var body = "一架战机，一道防线。"
	var action = "开始出击  /  ENTER"
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
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	var duration = 0.42 if kind == "bomb" else 0.22
	var count = int(duration * wav.mix_rate)
	var bytes = PackedByteArray()
	bytes.resize(count*2)
	for i in range(count):
		var t = float(i)/wav.mix_rate
		var freq = 240.0 + t*1200 if kind == "start" or kind == "clear" else 130.0 - t*90
		var value = sin(TAU*freq*t) * pow(1-float(i)/count,2) * 0.4
		bytes.encode_s16(i*2,int(value*32767))
	wav.data = bytes
	return wav

func _play(kind: String) -> void:
	if muted or audio == null: return
	audio.stream = sounds[kind]
	audio.play()

func _field_arc(p: Vector2, radius: float, color: Color, width: float) -> void:
	var bounds = Rect2(Vector2(2,2),FIELD - Vector2(4,4))
	for i in range(100):
		var a = p + Vector2.from_angle(i*TAU/100)*radius
		var b = p + Vector2.from_angle((i+1)*TAU/100)*radius
		if bounds.has_point(a) and bounds.has_point(b): draw_line(a,b,color,width,true)

# All curves are presentation-only, bounded (12 segments) and allocation-free of textures.
func _ribbon(p: Vector2, dir: Vector2, length: float, width: float, col: Color, curl: float = 1.0) -> void:
	var side = dir.orthogonal()
	# Four strips instead of 24 per-segment draw calls; the center stays luminous
	# while both outside edges and the tail decay to zero alpha.
	for layer in range(2):
		for sign_side in [-1,1]:
			var pts = PackedVector2Array()
			var colors = PackedColorArray()
			for i in range(13):
				var t = float(i)/12
				var center = p+dir*length*t+side*(sin(t*PI)*width*curl+layer*width*.35*t)
				pts.append(center)
				colors.append(Color(col,col.a*pow(1-t,1.4)*(.8 if layer==0 else .48)))
			for i in range(12,-1,-1):
				var t = float(i)/12
				var center = p+dir*length*t+side*(sin(t*PI)*width*curl+layer*width*.35*t)
				pts.append(center+side*sign_side*width*(1-t)*(.82 if layer==0 else .38))
				colors.append(Color(col,0))
			draw_polygon(pts,colors)

func _glyph_edge(pts: PackedVector2Array, col: Color, width: float = 1.3, closed: bool = true) -> void:
	draw_polyline(pts+PackedVector2Array([pts[0]]) if closed else pts,col,width,true)

func _sigil_arc(p: Vector2, radius: float, start: float, end: float, col: Color, width: float) -> void:
	draw_arc(p,radius,start,end,64,col,width,true)

func _hud_strip(rect: Rect2, col: Color) -> void:
	var a = rect.position
	var b = rect.end
	draw_polygon(PackedVector2Array([a,Vector2(b.x,a.y),b,Vector2(a.x,b.y)]),PackedColorArray([Color(col,.18),Color(col,0),Color(col,0),Color(col,.07)]))
	draw_line(a,Vector2(a.x,b.y),Color(col.lightened(.45),.9),1.5,true)
	draw_line(Vector2(a.x,b.y),Vector2(b.x,b.y),Color(col,.22),.8,true)
