extends "res://games/protocols/godot_party_default_protocol/ranked_round.gd"
const Arena: Script = preload("res://games/minigame/godot_party_default_star_wave/arena.gd")
const Visual: Script = preload("res://games/minigame/godot_party_default_star_wave/visual.gd")
var arenas: Array[RefCounted] = []
var displays: Array[Node2D] = []
var display_models: Array[RefCounted] = []
var team_by_player: Dictionary = {}
var accumulated: float = 0.0
var input_clock: float = 0.0
var team_mode: bool = false
var previous_local: Dictionary = {}
var overview: bool = false
var rendered_sequence: int = -1
var visual_age: float = 0.0
var panels: HBoxContainer

func build_game() -> void:
	team_mode = settings.get("mode", "个人赛") == "团队赛"
	heading.text = "星潮 · " + ("双队生存赛" if team_mode else "共同战场个人赛")
	footer.text = "WASD 移动 · Shift 精确移动 · X 炸弹 · 击败敌人 +100 / 受伤 −200 / Boss 每点有效伤害 +1"
	if team_mode:
		button(sidebar, "切换单队 / 双战场总览", func() -> void:
			overview = not overview
			_select_views())
	panels = HBoxContainer.new()
	panels.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panels.add_theme_constant_override("separation", 16)
	stage.add_child(panels)
	for index: int in (2 if team_mode else 1):
		var column: VBoxContainer = VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panels.add_child(column)
		label(column, "战场 " + str(index + 1) if team_mode else "共同战场")
		var surface: Control = Control.new()
		surface.size_flags_vertical = Control.SIZE_EXPAND_FILL
		surface.clip_contents = true
		column.add_child(surface)
		var visual: Node2D = Visual.new()
		var model: RefCounted = Arena.new()
		visual.core = model
		surface.add_child(visual)
		displays.append(visual)
		display_models.append(model)
		surface.resized.connect(_fit.bind(surface, visual))
		_fit.call_deferred(surface, visual)

func _select_views() -> void:
	for index: int in panels.get_child_count():
		panels.get_child(index).visible = not team_mode or overview or local_id.is_empty() or index == int(team_by_player.get(local_id, 0))

func _fit(surface: Control, visual: Node2D) -> void:
	var factor: float = minf(surface.size.x / 1440.0, surface.size.y / 960.0)
	visual.scale = Vector2.ONE * factor
	visual.position = (surface.size - Vector2(1440, 960) * factor) * 0.5

func start_game() -> void:
	for index: int in (2 if team_mode else 1):
		var roster: Array = []
		for seat: int in players.size():
			var team: int = seat % 2 if team_mode else 0
			team_by_player[players[seat].player_id] = team
			if team == index:
				roster.append({"id": players[seat].player_id, "name": players[seat].name, "color": player_color(players[seat].player_id).to_html()})
		var arena: RefCounted = Arena.new()
		arena.configure(roster, team_mode)
		arenas.append(arena)
	_select_views()

func tick_game(delta: float) -> void:
	input_clock += delta
	if input_clock >= 0.033:
		input_clock = 0
		send_action({"move": api.input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down"), "fire": get_window().has_focus() and (bool(api.config.get_own(&"auto_fire", true)) or api.input.is_pressed(&"star_fire")), "focus": api.input.is_pressed(&"star_focus"), "bomb": api.input.is_pressed(&"star_bomb")})
	if api.is_host():
		accumulated += delta
		while accumulated >= 1.0 / 120.0:
			for arena: RefCounted in arenas:
				arena.advance(1.0 / 120.0)
			accumulated -= 1.0 / 120.0
		var ended: bool = true
		for arena: RefCounted in arenas:
			if arena.state == "playing":
				ended = false
		if ended or elapsed >= float(settings.get("duration", 180)):
			_finish_match()
	visual_age += delta
	for model: RefCounted in display_models:
		if visual_age <= 0.15:
			for pilot_id: String in model.pilots:
				var pilot: Dictionary = model.pilots[pilot_id]
				if pilot.lives <= 0:
					continue
				var movement: Vector2 = pilot.move
				if pilot_id == local_id:
					movement = api.input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
				pilot.pos = (Vector2(pilot.pos) + movement * (155 if pilot.focus else 350) * delta).clamp(Vector2(24, 90), Vector2(1416, 926))
			for collection: Array in [model.bullets, model.shots]:
				for projectile: Dictionary in collection:
					projectile.pos += Vector2(projectile.vel) * delta
	for visual: Node2D in displays:
		visual.muted = not bool(api.config.get_own(&"sound", true))
		visual.visual_time += delta
		visual.queue_redraw()

func handle_action(id: String, data: Dictionary) -> void:
	arenas[team_by_player[id]].set_input(id, data)

func make_snapshot() -> Dictionary:
	var snapshots: Array = []
	for arena: RefCounted in arenas:
		snapshots.append(arena.snapshot())
	var raw: PackedByteArray = var_to_bytes(snapshots)
	return {"arenas": raw.compress(FileAccess.COMPRESSION_DEFLATE), "size": raw.size(), "time": maxf(0, float(settings.get("duration", 180)) - elapsed)}

func render_game() -> void:
	if view.is_empty() or not view.get("arenas") is PackedByteArray or int(view.get("size", 0)) > 4000000:
		return
	if int(view.get("_sequence", -1)) == rendered_sequence:
		return
	rendered_sequence = view._sequence
	visual_age = 0.0
	var decoded: Variant = bytes_to_var(view.arenas.decompress(int(view.size), FileAccess.COMPRESSION_DEFLATE))
	if not decoded is Array or decoded.size() != displays.size():
		return
	var lines: PackedStringArray = []
	for index: int in decoded.size():
		var snap: Dictionary = decoded[index]
		var arena_title: Label = panels.get_child(index).get_child(0) as Label
		arena_title.text = "战场 %d" % (index + 1) if team_mode else "共同战场"
		if not snap.boss.is_empty():
			arena_title.text += " · Boss %d / %d" % [ceili(snap.boss.hp), ceili(snap.boss.max_hp)]
		for key: String in snap:
			display_models[index].set(key, snap[key])
		if team_mode:
			lines.append("队伍 %d · 生存 %.1f 秒%s" % [index + 1, snap.survival, "（全队结束）" if snap.state == "lost" else ""])
		for id: String in snap.pilots:
			var pilot: Dictionary = snap.pilots[id]
			if id == local_id:
				displays[index].muted = not bool(api.config.get_own(&"sound", true))
				if previous_local.is_empty():
					displays[index]._play("start")
				elif pilot.lives < previous_local.lives:
					displays[index]._play("hurt")
				elif pilot.bombs < previous_local.bombs:
					displays[index]._play("bomb")
				previous_local = pilot.duplicate()
			lines.append("%s%s  %d 分\n  生命 %d · 炸弹 %d · 击败 %d · 受伤 %d\n  Boss伤害 %d" % ["▶ " if id == local_id else "", pilot.name, pilot.score, pilot.lives, pilot.bombs, pilot.kills, pilot.hurt, int(pilot.boss_damage)])
	standings.text = "\n".join(lines)
	standings.add_theme_font_size_override("font_size", 18 if players.size() > 4 else 22)
	status.text = "剩余 %d 秒 · %s" % [ceili(view.time), "以全队最后一人的存活时长排名；积分用于展示" if team_mode else "按个人积分排名，同分并列"]

func _finish_match() -> void:
	var scores: Dictionary = {}
	var metrics: Dictionary = {}
	for arena: RefCounted in arenas:
		for id: String in arena.pilots:
			var pilot: Dictionary = arena.pilots[id]
			scores[id] = roundi(arena.survival * 1000) if team_mode else pilot.score
			metrics[id] = {"score": pilot.score, "kills": pilot.kills, "hurt": pilot.hurt, "boss_damage": floori(pilot.boss_damage), "time": roundi(arena.survival * 1000), "team": int(team_by_player[id]) + 1}
	finish_scores(scores, metrics, [{"key": "score", "title": "积分", "format": "integer"}, {"key": "time", "title": "战场生存", "format": "time"}, {"key": "kills", "title": "击败敌人", "format": "integer"}, {"key": "hurt", "title": "受伤", "format": "integer"}, {"key": "boss_damage", "title": "Boss伤害", "format": "integer"}])

func player_left(id: String) -> void:
	if team_by_player.has(id):
		arenas[team_by_player[id]].pilots[id].lives = 0
