extends "res://ui/database/postgres_client.gd"

## Fake startup process for headless integration tests. Overridden methods
## never create a Windows process, regardless of launcher flag.

var allow_fake_launch := false
var have_fake_credentials := true
var launch_calls := 0


func _can_launch_local_service() -> bool:
	return allow_fake_launch


func _startup_script_path() -> String:
	## A real, harmless local file lets the client exercise launch gating.
	return ProjectSettings.globalize_path("res://project.godot")


func _has_saved_credentials() -> bool:
	## Synthetic prerequisite. Real tests never read/decrypt any credentials.
	return have_fake_credentials


func _start_local_service_process() -> Dictionary:
	launch_calls += 1
	return {"ok": true, "pid": 1}
