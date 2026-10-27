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
		var col = Color("e9bf8f") if e.type=="gunner" else Color("b7a3df") if e.type=="weaver" else Color("df96ad")
		_aura_at(e.pos,Vector2.ONE*e.radius*3.4,Color(col,.12))
	if not core.boss.is_empty():
		var p: Vector2 = core.boss.pos
		_aura_at(p,Vector2(220,160),Color(.62,.53,.8,.16))
		for side in [-1,1]: _aura_at(p+Vector2(side*94,7),Vector2(65,65),Color(.8,.55,.65,.12))
	for shot in core.shots: _aura_at(shot.pos,Vector2(13,30),Color(CYAN,.27))
	for b in core.bullets:
		var original: Color = b.get("color",Color("ff70c8"))
		var col = Color("df96ad") if original.r>original.b else Color("c0ace7")
		if original.g>.65 and original.r>.8: col=Color("f2c58e")
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

# Filled vector artwork rasterized at 4x and linearly sampled. No contour strokes.
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
		var svg = '<svg xmlns="http://www.w3.org/2000/svg" width="%s" height="%s"><defs><linearGradient id="v" x1="0" y1="0" x2="0.65" y2="1"><stop stop-color="#%s"/><stop offset="0.48" stop-color="#%s"/><stop offset="1" stop-color="#%s"/></linearGradient></defs><polygon points="%s" fill="url(#v)"/></svg>' % [size.x,size.y,col.lightened(.32).to_html(false),col.to_html(false),col.darkened(.30).to_html(false),points]
		var img = Image.new()
		img.load_svg_from_string(svg,4.0)
		_bleed_transparent_rgb(img,col)
		img.generate_mipmaps()
		shape_cache[key] = ImageTexture.create_from_image(img)
	draw_texture_rect(shape_cache[key],Rect2(bounds.position-Vector2.ONE*2,bounds.size+Vector2.ONE*4),false,Color(1,1,1,col.a))

func _soft_orb(p: Vector2, r: float, col: Color) -> void:
	var key = "orb"+col.to_html(false)
	if not shape_cache.has(key):
		var svg = '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><defs><radialGradient id="v" cx="38%%" cy="28%%" r="80%%"><stop stop-color="#%s"/><stop offset="0.52" stop-color="#%s"/><stop offset="1" stop-color="#%s"/></radialGradient></defs><circle cx="32" cy="32" r="30" fill="url(#v)"/></svg>' % [col.lightened(.5).to_html(false),col.to_html(false),col.darkened(.18).to_html(false)]
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
		_trail(p+Vector2(0,4),Vector2.DOWN,52,4,Color(CYAN,.42))
		# A filled antialiased capsule, not parallel bright contour strokes.
		draw_line(p+Vector2(0,6),p-Vector2(0,12),Color("a2ddd7"),3.0,true)
		_soft_orb(p+Vector2(0,6),1.5,Color("a2ddd7"))
		_soft_orb(p-Vector2(0,12),1.5,Color("a2ddd7"))
	for e in core.enemies: _enemy(e)
	if not core.boss.is_empty(): _enemy(core.boss)
	for pick in core.pickups:
		var p: Vector2 = pick.pos
		_soft_polygon(_poly(p,17,4,-PI/2),GOLD)
		_center(p+Vector2(0,5),"P" if pick.get("type","power")=="power" else "B",14,Color("483d29"))
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
		var pts = _poly(q,(3+n%3)*a,3,n+age*3)
		if Rect2(Vector2(8,8),FIELD-Vector2(16,16)).has_point(q):
			draw_polyline(pts+PackedVector2Array([pts[0]]),Color(.4,.9,1,a*.5),1,true)
	if age<.12: _neon_ring(p,5+age*80,Color(.8,1,1,a*.65),2)

func _bullet(b: Dictionary) -> void:
	var p: Vector2 = b.pos
	if not Rect2(Vector2(8,8),FIELD-Vector2(16,16)).has_point(p): return
	var r: float = b.get("radius",6)
	var original: Color = b.get("color",Color("ff70c8"))
	var col = Color("ed9eac") if original.r>original.b else Color("c0ace7")
	if original.g>.65 and original.r>.8: col=Color("f2c58e")
	# Solid circular body equals collision radius; no black border or luminous rim.
	_soft_orb(p,r,col)

func _diamond(p: Vector2, radius: float, color: Color) -> void:
	draw_colored_polygon(_poly(p,radius,4,-PI/2),color)

func _enemy(e: Dictionary) -> void:
	var p: Vector2 = e.pos
	if not Rect2(Vector2(-150,-150),FIELD+Vector2(300,300)).has_point(p): return
	var kind: String = e.get("type","scout")
	var r: float = e.get("radius",19)
	var col = Color("e9bf8f") if kind=="gunner" else Color("b7a3df") if kind=="weaver" else Color("df96ad")
	if float(e.get("flash",0))>0: col=Color("f3dce7")
	if float(e.get("telegraph",0))>0:
		_trail(p+Vector2(0,r),Vector2.DOWN,110,8,Color(col,.12))
	if kind=="boss":
		col=Color("b4a0d5") if float(e.get("flash",0))<=0 else Color("f3dce7")
		_soft_polygon(_poly(p,r,6,PI/6),col)
		for side in [-1,1]:
			var wing = p+Vector2(side*(r+36),7)
			_soft_polygon(PackedVector2Array([p+Vector2(side*40,-8),wing+Vector2(0,-10),wing+Vector2(0,10),p+Vector2(side*40,10)]),col.darkened(.2))
			_soft_polygon(PackedVector2Array([wing+Vector2(-23,-27),wing+Vector2(23,-27),wing+Vector2(31,15),wing+Vector2(0,33),wing+Vector2(-31,15)]),col)
			_soft_orb(wing,9,Color("eab3c5"))
			_trail(wing+Vector2(0,-25),Vector2.UP,30,9,Color(col,.28))
		_soft_orb(p,17,Color("ead4e5"))
	elif kind=="gunner":
		_soft_polygon(_poly(p,r*1.2,6,PI/6),col)
		for side in [-1,1]:
			_soft_polygon(PackedVector2Array([p+Vector2(side*6-3,0),p+Vector2(side*6+3,0),p+Vector2(side*6+3,r*1.3),p+Vector2(side*6-3,r*1.3)]),col.darkened(.12))
		_soft_orb(p,5,Color("f6e0bd"))
	elif kind=="weaver":
		_soft_polygon(_poly(p,r*1.3,4,0),col)
		_soft_orb(p,5,Color("e6d9f5"))
	else:
		_soft_polygon(PackedVector2Array([p+Vector2(-r,-r*.6),p+Vector2(0,r*1.3),p+Vector2(r,-r*.6),p+Vector2(0,-r*.2)]),col)

func _player() -> void:
	var p: Vector2 = core.player
	if core.state=="lost": return
	var alpha = .45 if core.invulnerable>0 and sin(visual_time*25)>0 else 1.0
	var flame = 45+10*sin(visual_time*31)
	for side in [-1,1]:
		_trail(p+Vector2(side*13,12),Vector2.DOWN,flame,6,Color(CYAN,alpha*.40))
	var pts=PackedVector2Array([p+Vector2(0,-27),p+Vector2(10,-3),p+Vector2(26,17),p+Vector2(9,11),p+Vector2(0,17),p+Vector2(-9,11),p+Vector2(-26,17),p+Vector2(-10,-3)])
	_soft_polygon(pts,Color("8bd5d2")*Color(1,1,1,alpha))
	_soft_polygon(PackedVector2Array([p+Vector2(0,-17),p+Vector2(4,-2),p+Vector2(0,6),p+Vector2(-4,-2)]),Color("507e9a")*Color(1,1,1,alpha))
	if core.focused: _soft_orb(p,4,Color("ffffff"))

func _hud() -> void:
	# Small translucent edge overlays; the playfield continues behind them.
	draw_style_box(_hud_style(), Rect2(20, 18, 254, 44))
	_text(Vector2(36, 47), "分数  %08d" % core.score, 22, Color("effaf5"))
	draw_style_box(_hud_style(), Rect2(FIELD.x - 360, 18, 280, 44))
	_diamond(Vector2(FIELD.x - 337, 40), 7, CYAN)
	_text(Vector2(FIELD.x - 320, 47), "生命 %d" % core.lives, 20, Color("effaf5"))
	draw_arc(Vector2(FIELD.x - 213, 40), 7, 0, TAU, 24, GOLD, 2)
	_text(Vector2(FIELD.x - 197, 47), "脉冲 %d" % core.bombs, 20, GOLD)
	draw_style_box(_hud_style(), Rect2(FIELD.x - 64, 18, 44, 44))
	for x in [FIELD.x - 47, FIELD.x - 37]:
		draw_line(Vector2(x, 32), Vector2(x, 48), Color("c1d7df"), 3)
	if not core.boss.is_empty():
		var bar_width = minf(460, FIELD.x * 0.34)
		var left = (FIELD.x - bar_width) * 0.5
		draw_style_box(_hud_style(), Rect2(left - 12, 10, bar_width + 24, 46))
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
	_soft_polygon(_poly(Vector2(720,260),48,6,PI/6),Color("8bd5d2"))
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
