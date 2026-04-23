@abstract
class_name NetBase
extends Node
## Base class for syncronized nodes

## Snapshot history size. MUST be a power of 2
const BUFFER_SIZE := 256
const _BUFFER_MASK := BUFFER_SIZE - 1

var _initial_snap: Snapshot

var _buffer: Array[Snapshot]

func _init() -> void:
	_initial_snap = Snapshot.new()
	_buffer.resize(BUFFER_SIZE)
	for n in _BUFFER_MASK:
		_buffer[n] = Snapshot.new()

## Should be called each tick
@abstract func _on_tick() -> void

## Handles receiving data from network
@abstract func _decode(tick: int, data: PackedByteArray) -> void

## Handles gathering data for the network
@abstract func _encode(tick: int) -> PackedByteArray

## Adds a variable to all snapshots in buffer and to inital snapshot
func _add_variable(path: NodePath) -> void:
	var node := get_node(NodePath(path))
	var var_path := NodePath(path.get_concatenated_subnames()).get_as_property_path()
	_initial_snap.append(node, var_path)
	for n in BUFFER_SIZE:
		_buffer[n].append(node, var_path)

## Returns true if has snapshot with matching tick.
func has_snapshot(tick: int) -> bool:
	return _buffer[tick & _BUFFER_MASK].tick == tick

## Gets snapshot at specified tick.
## Should call [method has_snapshot] to verify if it's tick matches.
func get_snapshot(tick: int) -> Snapshot:
	return _buffer[tick & _BUFFER_MASK]

## Resets buffer to inital states
func reset_buffer() -> void:
	for n in BUFFER_SIZE:
		_buffer[n] = _initial_snap.duplicate()
