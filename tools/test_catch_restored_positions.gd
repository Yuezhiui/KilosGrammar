extends SceneTree

# Protect the user's independent editor-authored Catch character groups from
# reparenting regressions. This test never opens camera or database.
const CATCH := preload("res://ui/minigames/catch_word.tscn")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game := CATCH.instantiate() as Control
	_check(not game.has_node("CharacterRig"), "obsolete CharacterRig hierarchy removed")
	var boy := game.get_node("Boy") as Node2D
	var collected := game.get_node("CollectedWords") as Node2D
	_check(boy.position.is_equal_approx(Vector2(640.0, 620.0)), "current editor-authored Boy baseline preserved")
	_check(collected.get_parent() == game, "collected words independent of every character")
	_check((boy.get_node("Body") as Sprite2D).position.is_equal_approx(Vector2(0.136, -209.87)), "original Boy body offset")
	_check((boy.get_node("Basket") as Sprite2D).position.is_equal_approx(Vector2(0.136, -149.89)), "original Boy basket offset")
	for name in ["Boy", "Girl", "Grandma", "Grandpa"]:
		var group := game.get_node(name) as Node2D
		var body := group.get_node("Body") as Sprite2D
		var basket := group.get_node("Basket") as Sprite2D
		_check(group.get_parent() == game, name + " is a separately editable root sibling")
		_check(body.z_index < collected.z_index and collected.z_index < basket.z_index,
			name + " body, collected words, and basket layering unchanged")
		_check(absf(body.position.y - basket.position.y + 60.0) < 10.0,
			name + " relative body/basket vertical gap preserved")
	game.free()
	print("CATCH RESTORED POSITION QA: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)

func _check(yes: bool, reason: String) -> void:
	if not yes:
		failures += 1
		printerr("CATCH RESTORED POSITION QA FAIL: ", reason)
