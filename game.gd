extends "res://games/protocols/godot_party_default_protocol/ranked_round.gd"

## Content-owned gameplay rules, independent of package compatibility.
static func party_definition() -> Dictionary:
	return {"player_counts": [1, 2, 3, 4, 5, 6, 7, 8], "player_count_rules": [{"when": {"mode": "团队赛"}, "counts": [2, 4, 6, 8]}], "tags": ["original"]}

const Arena: Script = preload("res://games/minigame/gp_star_wave/arena.gd")
const Display: PackedScene = preload("res://games/minigame/gp_star_wave/arena_display.tscn")
var arenas: Array[RefCounted] = []
var displays: Array[Node2D] = []
var display_models: Array[RefCounted] = []
var team_by_player: Dictionary = {}
var accumulated: float = 0.0
var network_clock: float = 0.0
const COLLECTIONS: Array[String] = ["enemies", "boss", "shots", "bullets", "pickups", "effects", "damage_waves", "cancel_effects"]
var _next_entity: int = 0
var _published: Dictionary = {}
var _event_revisions: Dictionary = {}
var _received_events: Dictionary = {}
var _entities: Dictionary = {}
var _input_sequence: int = 0
var _input_sequences: Dictionary = {}
var _motion_sequence: int = 0
var _received_motion: int = 0
var _pending_motion: Dictionary = {}
var _bomb_down: bool = false
var input_clock: float = 0.0
var previous_action: Dictionary = {}
var team_mode: bool = false
var previous_local: Dictionary = {}
var rendered_sequence: int = -1
var visual_age: float = 0.0
var victory_outro: float = 0.0
var surfaces: Array[Control] = []
@onready var hud: MarginContainer = %HUD
@onready var lives_label: Label = %Lives
@onready var score_label: Label = %Score

func build_game() -> void:
	team_mode = settings.get("mode", "个人赛") == "团队赛"
	hud.hide()
	for index: int in (2 if team_mode else 1):
		var surface: Control = %Arena if index == 0 else Display.instantiate()
		if index > 0:
			stage.add_child(surface)
		surfaces.append(surface)
		var visual: Node2D = surface.get_node("Visual")
		var model: RefCounted = Arena.new()
		visual.core = model
		displays.append(visual)
		display_models.append(model)
		surface.resized.connect(_fit.bind(surface, visual))
		_fit.call_deferred(surface, visual)

func _select_views() -> void:
	# A spectator follows the first arena; participants always see their own team.
	var visible_arena: int = int(team_by_player[local_id]) if not local_id.is_empty() else 0
	for index: int in surfaces.size():
		surfaces[index].visible = index == visible_arena
	hud.visible = not local_id.is_empty()

func _fit(surface: Control, visual: Node2D) -> void:
	# Fill the viewport while keeping the complete shared simulation field visible.
	visual.scale = surface.size / Vector2(1440, 960)
	visual.position = Vector2.ZERO

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
	var movement: Vector2 = api.input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	var focus: bool = api.input.is_pressed(&"star_focus")
	var action: Dictionary = {"move": movement, "fire": not api.input.input_blocked and get_window().has_focus() and (bool(api.config.get_own(&"auto_fire", true)) or api.input.is_pressed(&"star_fire")), "focus": focus, "bomb": api.input.is_pressed(&"star_bomb")}
	input_clock += delta
	if action.bomb and not _bomb_down:
		send_action({"kind": "bomb"})
	_bomb_down = action.bomb
	if not running:
		return
	if input_clock >= 0.05 or (movement == Vector2.ZERO and previous_action.get("move", Vector2.ZERO) != Vector2.ZERO):
		input_clock = 0.0
		previous_action = action
		_input_sequence += 1
		action["seq"] = _input_sequence
		action.bomb = false
		if not local_id.is_empty():
			var error: Error = api.net.send_to_host(&"star/input", action, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, 1)
			if error != OK:
				_transport_failed(error)
				return
	if api.is_host():
		accumulated += delta
		while accumulated >= 1.0 / 120.0:
			for arena: RefCounted in arenas:
				arena.advance(1.0 / 120.0)
			accumulated -= 1.0 / 120.0
		network_clock += delta
		if network_clock >= 0.05:
			network_clock = 0.0
			publish()
			if not running:
				return
		var ended: bool = true
		for arena: RefCounted in arenas:
			if arena.state == "playing":
				ended = false
		# Allow the final Boss burst to reach every display before settlement covers it.
		if ended and arenas[0].state == "won":
			victory_outro += delta
			if victory_outro >= 0.7:
				_finish_match()
		elif ended or elapsed >= float(settings.get("duration", 480)):
			_finish_match()
	# Only pilot extrapolation has a short horizon. Scripted visual timelines run locally.
	var pilot_delta: float = minf(delta, maxf(0.0, 0.15 - visual_age))
	visual_age += delta
	for model: RefCounted in display_models:
		var remaining: float = delta
		while remaining > 0.0:
			var step: float = minf(remaining, 1.0 / 120.0)
			model.advance_presentation(step)
			for projectile: Dictionary in model.bullets:
				model.advance_projectile(projectile, step, true)
			for projectile: Dictionary in model.shots:
				model.advance_projectile(projectile, step, false)
			remaining -= step
		if pilot_delta > 0.0:
			model.advance_pilots(pilot_delta, local_id, movement, focus)

	for visual: Node2D in displays:
		visual.muted = not bool(api.config.get_own(&"sound", true))
		visual.visual_time += delta
		visual.advance_feedback(delta)
		visual.queue_redraw()

func handle_action(id: String, data: Dictionary) -> void:
	if data.get("kind") == "bomb":
		arenas[team_by_player[id]].request_bomb(id)

func render_game() -> void:
	if local_id.is_empty() or not team_by_player.has(local_id):
		return
	var model: RefCounted = display_models[team_by_player[local_id]]
	if not model.pilots.has(local_id):
		return
	var pilot: Dictionary = model.pilots[local_id]
	var visual: Node2D = displays[team_by_player[local_id]]
	if previous_local.is_empty():
		visual._play("start")
	elif pilot.lives < previous_local.lives:
		visual._play("hurt")
	elif pilot.bombs < previous_local.bombs:
		visual._play("bomb")
	previous_local = pilot.duplicate()
	lives_label.text = api.i18n.text(&"hud.lives", {"lives": pilot.lives})
	score_label.text = api.i18n.text(&"hud.score", {"score": pilot.score})

func _finish_match() -> void:
	var scores: Dictionary = {}
	var metrics: Dictionary = {}
	for arena: RefCounted in arenas:
		for id: String in arena.pilots:
			var pilot: Dictionary = arena.pilots[id]
			scores[id] = (1000000000 if arena.state == "won" else roundi(arena.survival * 1000)) if team_mode else pilot.score
			metrics[id] = {"score": pilot.score, "kills": pilot.kills, "hurt": pilot.hurt, "boss_damage": floori(pilot.boss_damage), "stages": arena.cleared_stages, "time": roundi(arena.survival * 1000), "team": int(team_by_player[id]) + 1}
	finish_scores(scores, metrics, [{"key": "stages", "title": "通过关卡", "format": "integer"}, {"key": "score", "title": "积分", "format": "integer"}, {"key": "time", "title": "战场生存", "format": "time"}, {"key": "kills", "title": "击败敌人", "format": "integer"}, {"key": "hurt", "title": "受伤", "format": "integer"}, {"key": "boss_damage", "title": "Boss伤害", "format": "integer"}])

func player_left(id: String) -> void:
	if team_by_player.has(id):
		arenas[team_by_player[id]].pilots[id].lives = 0

## Stable births/deaths and changed facts are reliable. Projectile trajectories never repeat.
func publish() -> void:
	if not running or not api.is_host():
		return
	_motion_sequence += 1
	for index: int in arenas.size():
		var arena: RefCounted = arenas[index]
		var previous: Dictionary = _published.get(index, {"facts": {}, "pilots": {}, "objects": {}})
		var facts: Dictionary = {}
		var saved_facts: Dictionary = {}
		for field: String in ["state", "stage_index", "cleared_stages", "cleared", "stage_label"]:
			saved_facts[field] = arena.get(field)
			if not previous.facts.has(field) or previous.facts[field] != saved_facts[field]:
				facts[field] = saved_facts[field]
		var pilot_events: Dictionary = {}
		var pilot_motion: Dictionary = {}
		var saved_pilots: Dictionary = {}
		for id: String in arena.pilots:
			var pilot: Dictionary = arena.pilots[id]
			var old: Dictionary = previous.pilots.get(id, {})
			var changes: Dictionary = {}
			var saved: Dictionary = {}
			for field: String in ["name", "color", "lives", "bombs", "power", "score", "kills", "hurt", "boss_damage"]:
				saved[field] = pilot[field]
				if not old.has(field) or old[field] != pilot[field]:
					changes[field] = pilot[field]
			if old.is_empty() or pilot.invulnerable > old.invulnerable:
				changes["invulnerable"] = pilot.invulnerable
			saved["invulnerable"] = pilot.invulnerable
			if old.is_empty():
				changes["pos"] = pilot.pos
				changes["move"] = Vector2.ZERO
				changes["focus"] = false
			if not changes.is_empty():
				pilot_events[id] = changes
			saved_pilots[id] = saved
			pilot_motion[id] = {"pos": pilot.pos, "move": pilot.move, "focus": pilot.focus}
		var spawned: Array = []
		var updated: Array = []
		var live: Dictionary = {}
		for collection: String in COLLECTIONS:
			var values: Array = ([arena.boss] if not arena.boss.is_empty() else []) if collection == "boss" else arena.get(collection)
			for object: Dictionary in values:
				if not object.has("_net_id"):
					_next_entity += 1
					object["_net_id"] = _next_entity
				var id: int = object._net_id
				var old: Dictionary = previous.objects.get(id, {})
				var tracked: Dictionary = {}
				if collection in ["enemies", "boss"]:
					for field: String in ["hp", "stage", "phase", "warning_angle", "attack_allowed", "attack_index", "choreography_slot", "move_from", "move_to", "phrase"]:
						if object.has(field):
							tracked[field] = object[field]
				live[id] = {"collection": collection, "facts": tracked, "telegraph": object.get("telegraph", 0.0), "attack_telegraph": object.get("attack_telegraph", 0.0)}
				if old.is_empty():
					var initial: Dictionary = object.duplicate(true)
					for field: String in ["passed_waves", "previous", "damage", "timer", "aim_timer", "grazed", "burst_left", "spiral_tick"]:
						initial.erase(field)
					spawned.append({"id": id, "collection": collection, "data": initial})
				else:
					var changes: Dictionary = {}
					for field: String in tracked:
						if not old.facts.has(field) or old.facts[field] != tracked[field]:
							changes[field] = tracked[field]
					for timer: String in ["telegraph", "attack_telegraph"]:
						if object.has(timer) and float(object[timer]) > float(old[timer]):
							changes[timer] = object[timer]
					if changes.has("phase") or changes.has("choreography_slot"):
						for field: String in ["cycle_time", "telegraph", "phase_time", "pattern_rotation"]:
							if object.has(field):
								changes[field] = object[field]
					if not changes.is_empty():
						updated.append({"id": id, "data": changes})
		var removed: Array[int] = []
		for id: int in previous.objects:
			if not live.has(id):
				removed.append(id)
		var revision_value: int = _event_revisions.get(index, 0)
		if not facts.is_empty() or not pilot_events.is_empty() or not spawned.is_empty() or not updated.is_empty() or not removed.is_empty():
			revision_value += 1
			_event_revisions[index] = revision_value
			var event: Dictionary = {"arena": index, "revision": revision_value, "at_msec": api.net.host_time_msec(),
				"facts": facts, "pilots": pilot_events, "spawned": spawned, "updated": updated, "removed": removed}
			if not _send_arena(index, &"star/events", event, MultiplayerPeer.TRANSFER_MODE_RELIABLE, 0):
				return
		_published[index] = {"facts": saved_facts, "pilots": saved_pilots, "objects": live}
		if not _send_arena(index, &"star/motion", {"arena": index, "revision": revision_value,
			"sample": _motion_sequence, "pilots": pilot_motion}, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, 2):
			return

func _send_arena(index: int, topic: StringName, payload: Dictionary, mode: MultiplayerPeer.TransferMode, channel: int) -> bool:
	for player: Dictionary in api.get_room_players():
		if not player.connected or int(team_by_player.get(player.player_id, 0)) != index:
			continue
		var error: Error = api.net.send_to_player(player.player_id, topic, payload, mode, channel)
		if error != OK:
			_transport_failed(error)
			return false
	return true

func _message(sender: Dictionary, topic: StringName, payload: Variant) -> void:
	if topic not in [&"star/input", &"star/events", &"star/motion"]:
		super._message(sender, topic, payload)
		return
	if not running or not payload is Dictionary:
		return
	if topic == &"star/input":
		if not api.is_host() or not payload.get("seq") is int:
			return
		for player: Dictionary in api.get_players():
			var id: String = player.player_id
			if player.connected and id in sender.player_ids and not disconnected.has(id) and payload.seq > int(_input_sequences.get(id, 0)):
				_input_sequences[id] = payload.seq
				arenas[team_by_player[id]].set_input(id, payload)
				return
		return
	if sender.peer_id != 1 or not payload.get("arena") is int or payload.arena < 0 or payload.arena >= display_models.size() or not payload.get("revision") is int:
		return
	var index: int = payload.arena
	var last: int = _received_events.get(index, 0)
	if topic == &"star/motion":
		if not payload.get("sample") is int or payload.sample <= _received_motion or not payload.get("pilots") is Dictionary or payload.revision < last:
			return
		_received_motion = payload.sample
		if payload.revision > last:
			_pending_motion = payload
		else:
			_apply_motion(payload)
		return
	if payload.revision <= last:
		return
	if payload.revision != last + 1 or not payload.get("facts") is Dictionary or not payload.get("pilots") is Dictionary or not payload.get("spawned") is Array or not payload.get("updated") is Array or not payload.get("removed") is Array or not payload.get("at_msec") is int:
		_transport_failed(ERR_INVALID_DATA)
		return
	var model: RefCounted = display_models[index]
	for key: String in payload.facts:
		if key not in ["state", "stage_index", "cleared_stages", "cleared", "stage_label"]:
			return
		model.set(key, payload.facts[key])
	for id: String in payload.pilots:
		if not team_by_player.has(id) or not payload.pilots[id] is Dictionary:
			return
		if not model.pilots.has(id):
			model.pilots[id] = {}
		model.pilots[id].merge(payload.pilots[id], true)
		if not model.pilot_draw_positions.has(id):
			model.pilot_draw_positions[id] = model.pilots[id].pos
	var delay: float = clampf(float(api.net.host_time_msec() - payload.at_msec) / 1000.0, 0.0, 1.0)
	for entry: Variant in payload.spawned:
		if not entry is Dictionary or not entry.get("id") is int or entry.get("collection") not in COLLECTIONS or not entry.get("data") is Dictionary:
			_transport_failed(ERR_INVALID_DATA)
			return
		var object: Dictionary = entry.data.duplicate(true)
		_entities[entry.id] = {"arena": index, "collection": entry.collection, "data": object}
		if entry.collection == "boss":
			model.boss = object
		else:
			model.get(entry.collection).append(object)
		if entry.collection in ["bullets", "shots"]:
			model.advance_projectile(object, delay, entry.collection == "bullets")
		elif object.has("age"):
			object.age += delay
			if entry.collection == "enemies":
				object.pos = model.enemy_route_position(object, object.age)
			elif entry.collection == "pickups":
				object.pos.y += delay * 82.0
		if entry.collection == "effects":
			displays[index].consume_feedback([object])
	for entry: Variant in payload.updated:
		if not entry is Dictionary or not entry.get("id") is int or not entry.get("data") is Dictionary:
			return
		if _entities.has(entry.id):
			_entities[entry.id].data.merge(entry.data, true)
	for id: Variant in payload.removed:
		if not id is int:
			return
		if _entities.has(id):
			var entry: Dictionary = _entities[id]
			if entry.collection == "boss":
				model.boss = {}
			else:
				model.get(entry.collection).erase(entry.data)
			_entities.erase(id)
	_received_events[index] = payload.revision
	if not _pending_motion.is_empty() and _pending_motion.revision <= payload.revision:
		if _pending_motion.revision == payload.revision:
			_apply_motion(_pending_motion)
		_pending_motion.clear()
	render_game()

func _apply_motion(payload: Dictionary) -> void:
	var model: RefCounted = display_models[payload.arena]
	for id: String in payload.pilots:
		var motion: Variant = payload.pilots[id]
		if not model.pilots.has(id) or not motion is Dictionary or not motion.get("pos") is Vector2 or not motion.pos.is_finite() or not motion.get("move") is Vector2 or not motion.move.is_finite() or not motion.get("focus") is bool:
			continue
		model.pilots[id].merge(motion, true)
	visual_age = 0.0

func _transport_failed(error: Error) -> void:
	party_stop(&"star_transport")
	api.fail("star_transport", error_string(error))
