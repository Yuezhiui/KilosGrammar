extends "res://ui/main_menu/main_menu.gd"

# Test-only router: never launch, probe or write to the local PostgreSQL API
# while exercising synthetic camera and teacher setup navigation.
func _start_database_client() -> void:
	database_client = null
	database_online = false
	database_registration_pending = false
	database_pending_route.clear()
	database_registration_request_id = -1
