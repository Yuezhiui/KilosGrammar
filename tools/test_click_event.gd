extends SceneTree
func _init():
    call_deferred("_test")
func _test():
    var packed := load("res://ui/secondary/settings/settings.tscn") as PackedScene
    var scene := packed.instantiate() as Control
    root.add_child(scene)
    await process_frame
    var check := scene.find_child("FullscreenCheck", true, false) as CheckButton
    print("Initial check pressed: ", check.button_pressed)

    # Send a real GUI input event
    var mb := InputEventMouseButton.new()
    mb.button_index = MOUSE_BUTTON_LEFT
    mb.pressed = true
    mb.position = Vector2(10, 10)
    check._gui_input(mb)
    mb.pressed = false
    check._gui_input(mb)

    print("After click event: check pressed=", check.button_pressed)
    print("Window mode now: ", DisplayServer.window_get_mode())
    quit(0)
