## Business-owned setting defaults, constraints and UI hierarchy. No runtime side effects.
extends RefCounted

static func schema() -> Dictionary:
	return {
		"schema_format": 3,
		"settings_version": 1,
		"fields": {
			"mode": {
				"type": "string",
				"default": "个人赛",
				"title": "比赛模式",
				"audience": "room",
				"apply": "next_round",
				"values": [
					"个人赛",
					"团队赛"
				],
				"control": "select"
			},
			"duration": {
				"type": "int",
				"default": 180,
				"title": "比赛时限（秒）",
				"audience": "room",
				"apply": "next_round",
				"min": 30,
				"max": 600,
				"control": "number"
			},
			"move_left": {
				"type": "array",
				"action": "move_left",
				"default": [
					{
						"kind": "key",
						"code": 65,
						"physical": true
					}
				],
				"title": "向左",
				"audience": "local",
				"apply": "immediate",
				"control": "binding",
				"items": {
					"type": "object",
					"format": "binding"
				},
				"max_items": 2
			},
			"move_right": {
				"type": "array",
				"action": "move_right",
				"default": [
					{
						"kind": "key",
						"code": 68,
						"physical": true
					}
				],
				"title": "向右",
				"audience": "local",
				"apply": "immediate",
				"control": "binding",
				"items": {
					"type": "object",
					"format": "binding"
				},
				"max_items": 2
			},
			"move_up": {
				"type": "array",
				"action": "move_up",
				"default": [
					{
						"kind": "key",
						"code": 87,
						"physical": true
					}
				],
				"title": "向上",
				"audience": "local",
				"apply": "immediate",
				"control": "binding",
				"items": {
					"type": "object",
					"format": "binding"
				},
				"max_items": 2
			},
			"move_down": {
				"type": "array",
				"action": "move_down",
				"default": [
					{
						"kind": "key",
						"code": 83,
						"physical": true
					}
				],
				"title": "向下",
				"audience": "local",
				"apply": "immediate",
				"control": "binding",
				"items": {
					"type": "object",
					"format": "binding"
				},
				"max_items": 2
			},
			"star_fire": {
				"type": "array",
				"action": "star_fire",
				"default": [
					{
						"kind": "key",
						"code": 32,
						"physical": true
					}
				],
				"title": "射击",
				"audience": "local",
				"apply": "immediate",
				"control": "binding",
				"items": {
					"type": "object",
					"format": "binding"
				},
				"max_items": 2
			},
			"star_focus": {
				"type": "array",
				"action": "star_focus",
				"default": [
					{
						"kind": "key",
						"code": 4194325,
						"physical": true
					}
				],
				"title": "精确移动",
				"audience": "local",
				"apply": "immediate",
				"control": "binding",
				"items": {
					"type": "object",
					"format": "binding"
				},
				"max_items": 2
			},
			"star_bomb": {
				"type": "array",
				"action": "star_bomb",
				"default": [
					{
						"kind": "key",
						"code": 88,
						"physical": true
					}
				],
				"title": "清屏炸弹",
				"audience": "local",
				"apply": "immediate",
				"control": "binding",
				"items": {
					"type": "object",
					"format": "binding"
				},
				"max_items": 2
			},
			"auto_fire": {
				"type": "bool",
				"default": true,
				"title": "自动射击",
				"audience": "local",
				"apply": "immediate",
				"control": "toggle"
			},
			"sound": {
				"type": "bool",
				"default": true,
				"title": "音效",
				"audience": "local",
				"apply": "immediate",
				"control": "toggle"
			}
		},
		"layout": [
			{
				"id": "room",
				"title": "游戏规则",
				"expanded": true,
				"children": [
					{
						"field": "mode"
					},
					{
						"field": "duration"
					}
				]
			},
			{
				"id": "local",
				"title": "本机偏好",
				"expanded": true,
				"children": [
					{
						"field": "move_left"
					},
					{
						"field": "move_right"
					},
					{
						"field": "move_up"
					},
					{
						"field": "move_down"
					},
					{
						"field": "star_fire"
					},
					{
						"field": "star_focus"
					},
					{
						"field": "star_bomb"
					},
					{
						"field": "auto_fire"
					},
					{
						"field": "sound"
					}
				]
			}
		]
	}
