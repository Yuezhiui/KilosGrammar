extends "res://main_menu.gd"

## UI TEST FIXTURE ONLY. The runnable SceneTree entrypoint is
## test_postgres_csv_delete_menu.gd. The harness loads this subclass at runtime
## only AFTER project autoloads (including PoseService) are ready.


func _start_database_client() -> void:
	var fake_script := load("res://tools/test_postgres_csv_delete_mock.gd") as Script
	database_client = fake_script.new()
	database_client.name = "CsvDeleteInMemoryMockOnly"
	add_child(database_client)
	database_client.connect("request_finished", Callable(self, "_on_database_request_finished"))
	database_client.call("check_health", {"purpose": "startup"})


func _setup_title_music() -> void:
	pass


func _play_intro() -> void:
	intro_done = true
