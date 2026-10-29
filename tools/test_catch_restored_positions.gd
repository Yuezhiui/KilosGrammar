extends SceneTree

# Protect the user's independent editor-authored Catch character groups from
# reparenting regressions. This test never opens camera or database.
const CATCH := preload("res://ui/minigames/catch_the_word/catch_word.tscn")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game := CATCH.instantiate() as Control
	_check(not game.has_node("CharacterRig"), "obsolete CharacterRig hierarchy removed")
	var bear := game.get_node("Bear") as Node2D
	var collected := game.get_node("CollectedWords") as Node2D
	_check(bear.position.is_equal_approx(Vector2(640.0, 620.0)), "current editor-authored Bear baseline preserved")
	_check(collected.get_parent() == game, "collected words independent of every character")
	_check((bear.get_node("Body") as Sprite2D).position.is_equal_approx(Vector2(0.136, -217.303)), "new Bear body source-canvas alignment retained")
	_check((bear.get_node("Basket") as Sprite2D).position.distance_to(Vector2(6.105, -154.549)) <= 1.5,
		"Bear basket artwork retains its latest inspector-authored offset")
	for name in ["Bear", "Cat", "Dog", "Lion", "Panda"]:
		var group := game.get_node(name) as Node2D
		var body := group.get_node("Body") as Sprite2D
		var basket := group.get_node("Basket") as Sprite2D
		_check(group.get_parent() == game, name + " is a separately editable root sibling")
		_check(body.z_index < collected.z_index and collected.z_index < basket.z_index,
			name + " body, collected words, and basket layering unchanged")
		_check(body.position.y < basket.position.y and basket.position.y - body.position.y > 40.0
			and basket.position.y - body.position.y < 90.0,
			name + " independent source-aligned body/basket layers have a natural vertical gap")
	game.free()
	print("CATCH RESTORED POSITION QA: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)

func _check(yes: bool, reason: String) -> void:
	if not yes:
		failures += 1
		printerr("CATCH RESTORED POSITION QA FAIL: ", reason)
