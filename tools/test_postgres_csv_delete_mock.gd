extends "res://tools/test_postgres_mock_client.gd"

## Request-only fake. No sockets, subprocesses, real service, or real DB.
## The caller controls every result through inherited reply().
var mutations: Array[Dictionary] = []
var response_fixtures: Dictionary = {}
var admin_available := false


func has_local_admin_token() -> bool:
	## Fake presence of a per-user capability, never reads token files.
	return admin_available


func export_data(context: Dictionary = {}) -> int:
	return export_data_csv(context)


func export_data_csv(context: Dictionary = {}) -> int:
	return _record("export_data_csv", {}, context)


func export_csv(context: Dictionary = {}) -> int:
	return export_data(context)


func get_export_csv(context: Dictionary = {}) -> int:
	return export_data(context)


func import_data(csv_text: String, context: Dictionary = {}) -> int:
	return import_data_csv(csv_text, context)


func import_data_csv(csv_text: String, context: Dictionary = {}) -> int:
	mutations.append({"operation": "import_data_csv", "csv": csv_text})
	return _record("import_data_csv", {"csv": csv_text}, context)


func import_csv(csv_text: String, context: Dictionary = {}) -> int:
	return import_data(csv_text, context)


func delete_all_challenge(context: Dictionary = {}) -> int:
	return request_delete_all_challenge(context)


func request_delete_all_challenge(context: Dictionary = {}) -> int:
	return _record("request_delete_all_challenge", {}, context)


func request_delete_challenge(context: Dictionary = {}) -> int:
	return delete_all_challenge(context)


func get_delete_challenge(context: Dictionary = {}) -> int:
	return delete_all_challenge(context)


func delete_all_data(first: String, second: Variant = "", context: Dictionary = {}) -> int:
	## Accept named nonce + phrase contract and detect only the safe payload.
	var nonce := first
	var confirmation := String(second)
	if second is Dictionary:
		context = second
		confirmation = first
		nonce = ""
	elif first == "DELETE ALL DATA":
		confirmation = first
		nonce = String(second)
	mutations.append({"operation": "delete_all_data", "confirmation": confirmation, "nonce": nonce})
	return _record("delete_all_data",
		{"confirmation": confirmation, "nonce": nonce}, context)


func delete_data(confirmation: String, nonce: String = "", context: Dictionary = {}) -> int:
	return delete_all_data(confirmation, nonce, context)


func mutation_count() -> int:
	return mutations.size()
