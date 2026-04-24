class_name NetInput
extends NetBase
## Syncs client variables and events with server

## Max number of redundant input ticks to encode at once
const _MAX_REDUNDANCY := 5

## Paths to properties to be synced (ex: 'Node3D.SubNode3d:direction:x')
## Only used during initialization
@export var properties: PackedStringArray
## Paths to booleans to be synced (ex: 'CharacterBody3D:jump')
## These are only sent if true, useful for properties like 'jump' or 'attack'
## Only used during initialization
@export var events: PackedStringArray

## Should the server relay this input to other peers?
@export var is_relay: bool = false

## Number of properties managed
var property_count: int:
	get: return _initial_snap.size() - event_count
	set(_value): push_error("Property count cannot be set")
## Number of events managed
var event_count: int:
	get: return _event_count
	set(_value): push_error("Event Count cannot be set")
var _event_count: int = 0

## Tick of last input encoding
var _last_encoded_tick: int = 0

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
	if is_multiplayer_authority():
		# Record current tick
		var snap := get_snapshot(tick)
		snap.tick = tick
		snap.capture()
	elif multiplayer.is_server():
		pass # Handle remote input

func _encode(tick: int, peer: int = -1) -> PackedByteArray:
	if multiplayer.is_server() and not is_relay:
		return [] # Ignore this for encoding
	if not has_snapshot(tick) and not (is_multiplayer_authority() or multiplayer.is_server()):
		return [] # Nothing to encode
	var snap := get_snapshot(tick)
	var data := PackedByteArray()
	var redundent_ticks: int = 1
	if not multiplayer.is_server(): # Base this off number of ticks peer has missed
		redundent_ticks = mini(tick - _last_ack_tick.get(peer, 0), _MAX_REDUNDANCY)
	# Header
	data.resize(1)
	data.encode_u8(4, redundent_ticks)
	# Body
	data.append_array(snap.encode(null, _event_count))
	for n in range(1, (redundent_ticks)):
		data.append_array(get_snapshot(tick - n).encode(null, _event_count))
	_last_encoded_tick = tick
	return data

func _decode(tick: int, data: PackedByteArray, offset: int = 0) -> int:
	if not is_multiplayer_authority() or data.size() < 1 + offset:
		return -1 # This is invalid data
	var redundent_ticks := data.decode_u8(offset)
	var snap := get_snapshot(tick)
	snap.tick = tick
	var new_offset := offset + 1
	# No baseline used, we don't delta-encode input
	new_offset += snap.decode(data, new_offset, null, _event_count)
	for n in range(1, redundent_ticks):
		new_offset += get_snapshot(tick - n).decode(data, new_offset, null, _event_count)
	return new_offset
