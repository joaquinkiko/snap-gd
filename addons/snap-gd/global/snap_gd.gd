extends Node
## Handles network clock and snapshot delivery

## Sequence buffer size for outbound packets (MUST be power of 2)
const _SEQ_BUFFER_SIZE := 128
const _SEQ_BUFFER_MASK := _SEQ_BUFFER_SIZE - 1

## Nodes managed by this 
var managed_nodes: Array[Node]
## If node at this index should have _encode and _decode called on it
var _call_encode_decode: Array[bool]
## If node at this index should have _on_tick called on it
var _call_on_tick: Array[bool]
## Unique shared ID for node at this index
var _node_ids: PackedInt32Array

## Current outbound sequence number for each peer
var _peer_seq_current: Dictionary[int, int]
## Buffer of past outbound packets for each peer with sub-array of:
## [tick: int, ack: bool, node_ids: PackedInt32Array]
var _peer_seq_buffer: Dictionary[int, Array]
## Stores the last inbound sequence number received from each peer
var _peer_remote_seq: Dictionary[int, int]
## Stores a bitmask of the 8 prior inbound sequences relative to [member _peer_remote_seq]
var _peer_remote_ack_bits: Dictionary[int, int]
## Counts packets in sequence that were never acknowledged
var _peer_drop_count: Dictionary[int, int]
## Max bytes to send per packet
var _peer_packet_limit: Dictionary[int, int]

func _enter_tree() -> void:
	get_tree().node_added.connect(_node_added)
	get_tree().node_removed.connect(_node_removed)
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)

func _exit_tree() -> void:
	get_tree().node_added.disconnect(_node_added)
	get_tree().node_removed.disconnect(_node_removed)
	multiplayer.peer_connected.disconnect(_peer_connected)
	multiplayer.peer_disconnected.disconnect(_peer_disconnected)

## Check if new node should be registered
func _node_added(node: Node) -> void:
	if node is NetBase:
		register_node(node)
		if multiplayer.is_server(): # Server should assign ID
			# Last index will typically have the largest ID...
			var id: int = 0 if _node_ids.is_empty() else _node_ids[_node_ids.size() - 1] + 1
			var has_looped_once: bool = false
			while _node_ids.has(id): # ...but this is not guranteed, so double check
				id += 1
				if id > 0xFFFFFFFF: # Should not exceed 16-bits
					if has_looped_once:
						push_warning("NetNode capacity has been exceeded!")
						break # Safeguard against infinite loop
					# Loop back to check smaller numbers since we likely didn't start at 0
					else: id = 0
			_assign_node_id.rpc(id, node.get_path())

## Check if node needs to be deregistered
func _node_removed(node: Node) -> void:
	if managed_nodes.has(node):
		deregister_node(node)

func _peer_connected(peer: int) -> void:
	_peer_seq_current[peer] = 0
	_peer_drop_count[peer] = 0
	var base_array: Array[Array] = []
	base_array.resize(_SEQ_BUFFER_SIZE)
	for n in _SEQ_BUFFER_SIZE: base_array[n] = [-1, false, PackedInt32Array()]
	_peer_seq_buffer[peer] = base_array
	_peer_remote_seq[peer] = 0
	_peer_remote_ack_bits[peer] = 0
	_peer_packet_limit[peer] = 1408 # Later we'll have this loaded from user settings

func _peer_disconnected(peer: int) -> void:
	_peer_seq_current.erase(peer)
	_peer_drop_count.erase(peer)
	_peer_seq_buffer.erase(peer)
	_peer_remote_seq.erase(peer)
	_peer_remote_ack_bits.erase(peer)
	_peer_packet_limit.erase(peer)

## Registers a node to be managed
func register_node(node: Node) -> void:
	if managed_nodes.has(node):
		push_error("Attempting to register node that is already registered!")
		return
	managed_nodes.append(node)
	_call_encode_decode.append(node.has_method(&"_encode") and node.has_method(&"_decode"))
	_call_on_tick.append(node.has_method(&"_on_tick"))
	_node_ids.append(-1)

## Deregisters a node to no longer be managed
func deregister_node(node: Node) -> void:
	if not managed_nodes.has(node):
		push_error("Attempting to deregister node that is not registered!")
		return
	var index: int = managed_nodes.find(node)
	managed_nodes.erase(index)
	_call_encode_decode.erase(index)
	_call_on_tick.erase(index)
	_node_ids.erase(index)

## Called each tick
func _on_tick(tick: int) -> void:
	for n in managed_nodes.size(): if _call_on_tick[n]:
		managed_nodes[n].call(&"_on_tick", tick)

## Allows server to assign unique ID to a registered node.
## This assumes that all players have this node at the same [NodePath].
@rpc("authority", "call_local", "reliable")
func _assign_node_id(id: int, path: NodePath) -> void:
	var node := get_node(path)
	var index := managed_nodes.find(node)
	if node == null or index == -1:
		push_error("Missing node to assign ID to! This node cannot be syncronized!")
		# We should probably have somesort of handling to 'reattempt'?
		return
	if _node_ids.has(id): push_error("Assigning duplicate ID to node! This WILL cause issue!")
	_node_ids[index] == id

## Encodes nodes into a [PackedByteArray] for the given peer, and increments the sequence.
func _encode_packet(tick: int, peer: int) -> PackedByteArray:
	var seq := _peer_seq_current[peer]
	var slot: Array = _peer_seq_buffer[peer][seq & _SEQ_BUFFER_MASK]
	if slot[0] != -1 and not slot[1]: # Has a tick and ack == false
		_peer_drop_count[peer] += 1 # Count as dropped
	# Header
	var packet: PackedByteArray
	packet.resize(11)
	packet.encode_u32(0, tick)
	packet.encode_u16(4, seq)
	packet.encode_u16(6, _peer_remote_seq.get(peer, 0))
	packet.encode_u16(8, _peer_remote_ack_bits.get(peer, 0))
	# Body
	var packed_ids: PackedInt32Array
	var node_data: PackedByteArray
	for n in managed_nodes.size():
		if not _call_encode_decode[n]: continue
		if _node_ids[n] == -1: continue # pending ID assignment
		node_data = managed_nodes[n].call(&"_encode", tick, peer)
		if 2 + packet.size() + node_data.size() > _peer_packet_limit[peer]:
			continue # Won't fit, but we'll keep looking for something that will
		packet.resize(packet.size() + 2)
		packet.encode_u16(packet.size() - 2, _node_ids[n]) # Node ID
		packet.append_array(node_data)
		packed_ids.append(_node_ids[n])
		if packet.size() + 4 > _peer_packet_limit[peer]:
			break # We can't physcially fit anymore (4 is the VERY minimum size a node will need)
	packet.encode_u8(10, packed_ids.size()) # Update size in header
	# Record this to the sequence
	slot[0] = tick
	slot[1] = false
	slot[2] = packed_ids
	# Increment sequence, wrapping at u16 max
	_peer_seq_current[peer] = (seq + 1) & 0xFFFF
	return packet

## Decodes a [PackedByteArray] received from the given peer.
func _decode_packet(data: PackedByteArray, peer: int) -> void:
	if data.size() < 11: return # Too small to contain a valid header
	var tick: int = data.decode_u32(0)
	var seq: int = data.decode_u16(4)
	var last_acked: int = data.decode_u16(6)
	var ack_bits: int = data.decode_u16(8)
	var node_count: int = data.decode_u8(10)
	# Check if any of the acks are new to us
	_acknowledge_ack(peer, last_acked)
	for bit in 16: if ack_bits & (1 << bit): _acknowledge_ack(peer, (last_acked - 1 - bit))
	# Body
	var offset: int = 11
	for n in node_count:
		if offset + 2 > data.size(): return
		# Find which managed node owns this ID
		var node_index := _node_ids.find(data.decode_u16(offset))
		if node_index == -1:
			return  # We don't know sh*t about this "node"... probably just hasn't spawned yet
		if _call_encode_decode[node_index]:
			offset = managed_nodes[node_index].call(&"_decode", tick, data, offset + 2) + 2
	# We'll wait to record this until the end, that way if
	# there's an error reading, we aren't aknowledging it as received
	_record_received_sequence(peer, seq)

## Checks a if the provided sequence has been ack'ed, and
## if not it records the ack to all nodes in that sequence.
func _acknowledge_ack(peer: int, seq: int) -> void:
	if seq < _peer_seq_current[peer] - _SEQ_BUFFER_SIZE:
		return # Sequence is older than buffer
	var slot: Array = _peer_seq_buffer[peer][seq & _SEQ_BUFFER_MASK]
	if slot[0] == -1 or slot[1]: # Tick == -1 or ack == true
		return # No need to update
	slot[1] = true
	for node_id in slot[2]:
		var index: int = _node_ids.find(node_id)
		if index != -1 and _call_encode_decode[index]:
			managed_nodes[index].call(&"record_ack", peer, slot[0])

## Records a remote sequence as received locally.
func _record_received_sequence(peer: int, seq: int) -> void:
	if seq == _peer_remote_seq[peer]: return  # Duplicate sequence
	var delta := seq - _peer_remote_seq[peer]
	if delta < _SEQ_BUFFER_SIZE:
		# Shust shift 'em bits over and add the previous 'last_acked'
		_peer_remote_ack_bits[peer] = (_peer_remote_ack_bits[peer] << delta) | (1 << (delta - 1))
		# Technically we're recording up to 64 priors since int is 64-bit!
		# We aren't sending all of those over the network, but it is a fun fact...
		_peer_remote_seq[peer] = seq

## Uses output of [method encode_packet] to be received with [method decode_packet].
## IMPORTANT: These packets are delta-encoded and tailore to each peer,
## so DON'T send these to all peers, only send it to the peer it was encoded for.
@rpc("any_peer", "call_remote", "unreliable")
func _handle_raw_packet(packet: PackedByteArray) -> void:
	_decode_packet(packet, multiplayer.get_remote_sender_id())
