## Lightweight catalog data. Do not load gameplay scenes or scripts here.
extends RefCounted

static func party_definition() -> Dictionary:
	return {"player_counts": [1, 2, 3, 4, 5, 6, 7, 8], "player_count_rules": [{"when": {"mode": "团队赛"}, "counts": [2, 4, 6, 8]}], "tags": ["original"]}
