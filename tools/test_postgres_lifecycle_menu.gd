extends "res://tools/test_postgres_main_menu.gd"

const MOCK_LIFECYCLE_CLIENT := preload("res://tools/test_postgres_lifecycle_client.gd")


func _start_database_client() -> void:
	database_client = MOCK_LIFECYCLE_CLIENT.new()
	database_client.name = "TestOnlyLifecycleClient"
	add_child(database_client)
	database_client.connect("request_finished", Callable(self, "_on_database_request_finished"))
	database_client.connect("local_service_status_changed",
		Callable(self, "_on_database_local_service_status_changed"))
	database_client.call("ensure_local_service", {"purpose": "startup"})
