extends "res://tools/test_postgres_main_menu.gd"

const RECOVERY_MOCK := preload("res://tools/test_postgres_recovery_mock.gd")


func _start_database_client() -> void:
	database_client = RECOVERY_MOCK.new()
	database_client.name = "TestOnlyPostgresRecovery"
	add_child(database_client)
	database_client.connect("request_finished", Callable(self, "_on_database_request_finished"))
	database_client.connect("local_service_status_changed",
		Callable(self, "_on_database_local_service_status_changed"))
	database_client.call("ensure_local_service", {"purpose": "startup"})
