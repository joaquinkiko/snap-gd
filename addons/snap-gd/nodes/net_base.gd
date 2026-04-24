@abstract
class_name NetBase
extends Node
## Base class for syncronized nodes

## Snapshot history size. MUST be a power of 2
const BUFFER_SIZE := 256
const _BUFFER_MASK := BUFFER_SIZE - 1

var _initial_snap: Snapshot

var _buffer: Array[Snapshot]

## {Peer ID : tick}
var _last_ack_tick: Dictionary[int, int]

func _init() -> void:
	_initial_snap = Snapshot.new()
	_buffer.resize(BUFFER_SIZE)
	for n in _BUFFER_MASK:
		_buffer[n] = Snapshot.new()

func _enter_tree() -> void:
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(_connected_to_server)
	multiplayer.server_disconnected.connect(_server_disconnected)
	SnapGd.register_node(self)

func _exit_tree() -> void:
	SnapGd.deregister_node(self)

func _connected_to_server() -> void:
	pass

func _server_disconnected() -> void:
	pass

## Add initial value to [member _last_ack_tick]
func _peer_connected(id: int) -> void:
	_last_ack_tick[id] = -1

## Cleans up [member _last_ack_tick]
func _peer_disconnected(id: int) -> void:
	_last_ack_tick.erase(id)

## Should be called each tick
@abstract func _on_tick(tick: int) -> void

## Handles receiving data from network.
## Returns new offset after handling data.
@abstract func _decode(tick: int, data: PackedByteArray, offset: int = 0) -> int

## Handles gathering data for the network
@abstract func _encode(tick: int, peer: int = 0) -> PackedByteArray

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

## Gets snapshot of last acknowledged tick, or initial tick if not found.
## Pass -1 to use initial snapshot.
func get_last_ack_snap(peer: int) -> Snapshot:
	if peer == -1: return _initial_snap
	var snap := _buffer[_last_ack_tick[peer] & _BUFFER_MASK]
	if snap.tick == _last_ack_tick[peer]: return snap
	else: return _initial_snap

## Record that a peer has acknowledged receiving a snapshot at [param ack_tick].
func record_ack(peer_id: int, ack_tick: int) -> void:
	var old_ack: int = _last_ack_tick.get(peer_id, -1)
	if ack_tick > old_ack:
		_last_ack_tick[peer_id] = ack_tick
