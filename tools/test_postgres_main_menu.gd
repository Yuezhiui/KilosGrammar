extends "res://main_menu.gd"

## Allows the unmodified Main Menu scene and real panels to run without HTTP,
## microphone/camera calibration, database credentials, or background music.
const MOCK_CLIENT := preload("res://tools/test_postgres_mock_client.gd")


func _start_database_client() -> void:
	database_client = MOCK_CLIENT.new()
	database_client.name = "TestOnlyLocalPostgreSQLClient"
	add_child(database_client)
	database_client.connect("request_finished", Callable(self, "_on_database_request_finished"))
	database_client.call("check_health", {"purpose": "startup"})


func _setup_title_music() -> void:
	pass


func _play_intro() -> void:
	intro_done = true
