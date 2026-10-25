extends "res://tools/test_postgres_csv_delete_integration.gd"

## Supported direct Godot --script entry point. The test-only Main Menu
## subclass lives in test_postgres_csv_delete_menu_fixture.gd and MUST NOT be
## run as a SceneTree script: it extends the real UI Control and depends on
## PoseService, which is created only after SceneTree autoload startup.
##
## godot --headless --path . --script res://tools/test_postgres_csv_delete_menu.gd
##
## Inherit the existing camera-free/socket-free 166-assertion integration QA
## so this filename remains easy to execute without duplicating test code.
