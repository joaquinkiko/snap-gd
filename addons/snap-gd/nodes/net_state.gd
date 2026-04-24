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
	if multiplayer.is_server():
		# Record current tick
		var snap := get_snapshot(tick)
		snap.tick = tick
		snap.capture()
	elif is_multiplayer_authority():
		pass # Reconcile state
	else:
		pass # Interpolate state

func _encode(tick: int, peer: int = -1) -> PackedByteArray:
	if not (multiplayer.is_server() and has_snapshot(tick)):
		return [] # Nothing to encode
	var snap := get_snapshot(tick)
	var baseline := get_last_ack_snap(peer)
	var data := snap.encode(baseline, 0)
	return data

func _decode(tick: int, data: PackedByteArray, offset: int = 0) -> int:
	if multiplayer.is_server() or data.size() < offset:
		return -1 # This is invalid data
	var baseline_tick: int = _last_ack_tick.get(1, 0) # This SHOULD match server... need to verify
	var snap := get_snapshot(tick)
	var baseline := get_snapshot(baseline_tick)
	if baseline.tick != baseline_tick:
		baseline = _initial_snap
	snap.tick = tick
	return snap.decode(data, offset, baseline, 0) + offset
