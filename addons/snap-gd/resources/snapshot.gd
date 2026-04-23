class_name Snapshot
extends RefCounted
## Contains variables for syncing and serialization

## Tick that this snapshot belongs to
var tick: int = -1

# These arrays should always be equal size
var _nodes: Array[Node]
var _sub_paths: Array[NodePath]
var _types: Array[Variant.Type]
var _values: Array[Variant]

## Add new variable to track
func append(node: Node, var_path: NodePath) -> void:
	if node == null or var_path.is_empty(): return
	_nodes.append(node)
	_sub_paths.append(var_path)
	var current_value: Variant = get_value(_nodes.size() - 1)
	_types.append(typeof(current_value))
	_values.append(current_value)

## Erase tracked variable
func erase(node: Node, var_path: NodePath) -> void:
	for n in size():
		if _nodes[n] == node and _sub_paths[n] == var_path:
			_nodes.remove_at(n)
			_sub_paths.remove_at(n)
			_types.remove_at(n)
			_values.remove_at(n)
			break

## Returns number of tracked variables
func size() -> int:
	return _nodes.size()

## Erase all tracked variables
func clear() -> void:
	_nodes.clear()
	_sub_paths.clear()
	_types.clear()
	_values.clear()

## Creates new instance of this objects
func duplicate(deep: bool = false) -> Snapshot:
	var snap := Snapshot.new()
	snap._nodes = _nodes.duplicate(deep)
	snap._sub_paths = _sub_paths.duplicate(deep)
	snap._types = _types.duplicate(deep)
	snap._values = _values.duplicate(deep)
	return snap

## Returns true if this contains this index
func has_index(index: int) -> bool:
	return index >= _nodes.size() or index < 0

## Returns true if this contains this variable
func has_variable(node: Node, var_path: NodePath) -> bool:
	for n in size():
		if _nodes[n] == node and _sub_paths[n] == var_path:
			return true
	return false

## Returns [NodePath] of stored index.
## Use [param from] to specify path as relative to another Node.
func get_index_path(index: int, from: Node = null) -> NodePath:
	if not has_index(index) or _nodes[index] == null:
		return NodePath()
	var path: NodePath
	if from == null:
		path = _nodes[index].get_path()
	else:
		path = from.get_path_to(_nodes[index])
	path = NodePath("%s:%s"%[path, _sub_paths[index]])
	return path

## Gets local value at stored index. Does NOT validate that index exists.
func get_value(index: int) -> Variant:
	return _nodes[index].get_indexed(_sub_paths[index])

## Sets local value at stored index. Does NOT validate that index exists.
func set_value(index: int, value: Variant) -> void:
	_nodes[index].set_indexed(_sub_paths[index], value)

## Get type of variable at specified path
func get_type(index: int) -> Variant.Type:
	return _types[index]
