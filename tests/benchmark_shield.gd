extends SceneTree
const Core=preload("res://scripts/game_core.gd")
func _initialize():
	var samples: Array[float]=[]
	var peak:=0
	for round_index in 12:
		var c=Core.new()
		c.start(); c._next_wave_time=9999; c.invulnerable=0
		for i in 900:
			c._add_bullet(Vector2(24+(i%30)*47,24+(i/30)*30),Vector2(40,-20),5,Core.PINK)
		c._hit_player()
		for i in 80:
			var started=Time.get_ticks_usec()
			c.step(1.0/120,Vector2.ZERO,false,false,false)
			samples.append((Time.get_ticks_usec()-started)/1000.0)
			peak=maxi(peak,c.cancel_effects.size())
	samples.sort()
	print("SHIELD_BENCHMARK 12 x900-bullet fixtures /960 ticks; median_ms=",samples[samples.size()/2]," p95_ms=",samples[int(samples.size()*.95)]," max_ms=",samples.back()," peak_remnants=",peak)
	quit()
