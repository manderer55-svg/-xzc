extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _run() -> void:
	var counter := GeneratedNumber.new()
	counter.size = Vector2(180, 50)
	root.add_child(counter)
	await process_frame
	_check(counter.created_count == 1, "initial zero displayed")
	counter.text = "123456789"
	var high_water := counter.created_count
	var identities := counter.get_children().map(func(child: Node): return child.get_instance_id())
	for value in range(2000):
		counter.text = str(value)
		_check(counter.created_count == high_water, "changing score reuses sprites")
		var visible := 0
		for child: TextureRect in counter.get_children():
			if child.visible:
				visible += 1
		_check(visible == str(value).length(), "old digits hidden when value shrinks")
	_check(counter.get_children().map(func(child: Node): return child.get_instance_id()) == identities, "glyph identities remain stable")
	counter.text = "12"
	var original: Vector2 = counter.get_child(0).position
	counter.centered = true
	_check(counter.get_child(0).position.x > original.x, "centering updates existing glyph positions")
	counter.text = ""
	_check(counter.get_children().all(func(child: Node): return not child.visible), "empty counter leaves no stale digits")
	counter.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: %d generated-number reuse checks." % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)
