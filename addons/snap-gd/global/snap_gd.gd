extends Node
## Handles network clock and snapshot delivery

## Nodes managed by this 
var managed_nodes: Array[Node]
## If node at this index should have _encode and _decode called on it
var _call_encode_decode: Array[bool]
## If node at this index should have _on_tick called on it
var _call_on_tick: Array[bool]

## Registers a node to be managed
func register_node(node: Node) -> void:
	if managed_nodes.has(node):
		push_error("Attempting to register node that is already registered!")
		return
	managed_nodes.append(node)
	_call_encode_decode.append(node.has_method(&"_encode") and node.has_method(&"_decode"))
	_call_on_tick.append(node.has_method(&"_on_tick"))

## Deregisters a node to no longer be managed
func deregister_node(node: Node) -> void:
	if not managed_nodes.has(node):
		push_error("Attempting to deregister node that is not registered!")
		return
	var index: int = managed_nodes.find(node)
	managed_nodes.erase(index)
	_call_encode_decode.erase(index)
	_call_on_tick.erase(index)

## Called each tick
func _on_tick(tick: int) -> void:
	for n in managed_nodes.size(): if _call_on_tick[n]:
		managed_nodes[n].call(&"_on_tick", tick)

## Called to decode snapshot
func _decode(tick: int, data: PackedByteArray) -> void:
	var offset: int = 0
	var result: int 
	for n in managed_nodes.size(): if _call_encode_decode[n]:
		result = managed_nodes[n].call(&"_decode", tick, data, offset)
		if result == -1: # Error occured
			break # Stop decoding, we can't verify offset of future nodes
		offset += result

## Called to encode snapshot
func _encode(tick: int) -> PackedByteArray:
	var data: PackedByteArray
	for n in managed_nodes.size(): if _call_encode_decode[n]:
		managed_nodes[n].call(&"_encode", tick)
	return data
