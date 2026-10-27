extends SceneTree
const Core = preload("res://scripts/game_core.gd")
func _initialize():
	var c=Core.new()
	c.debug_set_boss(3)
	c.invulnerable=100
	var samples: Array[float]=[]
	var peak:=0
	for tick in 3600:
		var before:=Time.get_ticks_usec()
		c.step(1.0/120,Vector2.ZERO,false,false,false)
		if c.bullets.size()>200: samples.append((Time.get_ticks_usec()-before)/1000.0)
		peak=maxi(peak,c.bullets.size())
	samples.sort()
	print("SPIRAL_SIMULATION_BENCH samples=",samples.size()," peak=",peak," dense_tick_median_ms=",samples[samples.size()/2]," p95_ms=",samples[int(samples.size()*.95)])
	quit()
