class_name NetInput
extends NetBase
## Syncs client variables and events with server

## Paths to properties to be synced (ex: 'Node3D.SubNode3d:direction:x')
## Only used during initialization
@export var properties: PackedStringArray
## Paths to booleans to be synced (ex: 'CharacterBody3D:jump')
## These are only sent if true, useful for properties like 'jump' or 'attack'
## Only used during initialization
@export var events: PackedStringArray

## Number of properties managed
var property_count: int:
	get: return _initial_snap.size() - event_count
	set(_value): push_error("Property count cannot be set")
## Number of events managed
var event_count: int:
	get: return _event_count
	set(_value): push_error("Event Count cannot be set")
var _event_count: int = 0

func _enter_tree() -> void:
	for property in properties:
		_add_variable(NodePath(property))
	for event in events:
		_add_variable(NodePath(event))
	_event_count = events.size()
	properties.clear() # Clean-up memory
	events.clear()
	super._enter_tree()

func _on_tick(tick: int) -> void:
	pass

func _decode(tick: int, data: PackedByteArray) -> void:
	pass

func _encode(tick: int) -> PackedByteArray:
	var data: PackedByteArray
	return data
