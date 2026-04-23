class_name NetState
extends NetBase
## Syncs server variables with all clients

## Paths to properties to be synced (ex: 'Node3D.SubNode3d:position:x')
## Only used during initialization
@export var properties: PackedStringArray

## Number of properties managed
var property_count: int:
	get: return _initial_snap.size()
	set(_value): push_error("Property count cannot be set")

func _enter_tree() -> void:
	for property in properties:
		_add_variable(NodePath(property))
	properties.clear() # Clean-up memory
	super._enter_tree()

func _on_tick(tick: int) -> void:
	pass

func _decode(tick: int, data: PackedByteArray) -> void:
	pass

func _encode(tick: int) -> PackedByteArray:
	var data: PackedByteArray
	return data
