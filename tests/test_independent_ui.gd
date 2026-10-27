extends SceneTree
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok:bool,label:String):
	checks+=1
	if not ok:
		failures+=1
		push_error(label)
func key(scene,code):
	var event=InputEventKey.new(); event.keycode=code; event.pressed=true
	scene._unhandled_input(event)
func run():
	var scene=load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	# This fixture tests controls/layout, not audio playback; do not leave a playing stream at shutdown.
	scene.muted = true
	await process_frame
	scene.set_process(false)
	check(scene.core.state=="ready","initial ready")
	key(scene,KEY_ENTER); check(scene.core.state=="playing" and not scene.paused,"enter start")
	scene._process(.05); check(scene.core.elapsed>0 and scene.core.shots.size()>0,"automatic fire advances")
	key(scene,KEY_P); var elapsed:float=scene.core.elapsed; var bullets=scene.core.bullets.duplicate(true)
	scene._process(.05); key(scene,KEY_X)
	check(scene.paused and scene.core.elapsed==elapsed and scene.core.bullets==bullets and scene.core.bombs==3,"pause freezes state and rejects bomb")
	key(scene,KEY_ENTER); scene._process(.05)
	check(not scene.paused and scene.core.elapsed>elapsed,"resume works")
	scene._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(scene.paused,"focus loss pauses")
	key(scene,KEY_R); check(scene.core.elapsed==0 and scene.core.bombs==3 and not scene.paused,"restart from pause")
	key(scene,KEY_F); scene._process(.05); check(scene.core.shots.is_empty(),"auto fire toggle off")
	key(scene,KEY_X); check(scene.core.bombs==2,"X bomb")
	scene._process(.05); key(scene,KEY_SPACE); check(scene.core.bombs==1,"space bomb after frame")
	key(scene,KEY_P); key(scene,KEY_R)
	await create_timer(.4).timeout
	check(scene.core.elapsed==0 and scene.core.bombs==3 and scene.core.bullets.is_empty(),"restart no stale timer mutation")
	for dimensions in [Vector2i(960,640),Vector2i(1920,1080),Vector2i(800,1000)]:
		root.size=dimensions
		await process_frame
		check(is_instance_valid(scene) and scene.core.state=="playing","resizes retain game")
		check(scene.FIELD.is_equal_approx(scene.get_viewport_rect().size) and scene.core.field_size.is_equal_approx(scene.FIELD),"entire expanded viewport remains playable")
		check(scene.ORIGIN == Vector2.ZERO,"no sidebar offset")
		check(scene.core.player.x >= 24 and scene.core.player.x <= scene.FIELD.x - 24,"resize player remains inside field")
	scene.free()
	print("INDEPENDENT UI: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
