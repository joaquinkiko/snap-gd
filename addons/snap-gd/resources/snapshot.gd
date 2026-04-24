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

## Capture all local values and store them to this snapshot
func capture() -> void:
	for i in size():
		_values[i] = get_value(i)
 
## Take stored values and apply them locally
func apply() -> void:
	for i in size():
		set_value(i, _values[i])

## Encode values to a [PackedByteArray], using delta-encoding against [param baseline].
## Pass null [param baseline] to encode all variables unconditionally.
## 'Events' are the last [param event_count] entries, they aren't encoded when equal to false.
func encode(baseline: Snapshot = null, event_count: int = 0) -> PackedByteArray:
	var property_count: int = size() - event_count
	var flag_bytes: int = ceili(size() / 8.0) if size() > 0 else 0
	var data := PackedByteArray()
	data.resize(flag_bytes) # Blanks flags initially
	# Write body
	var body := PackedByteArray()
	for i in size():
		if i >= property_count: # Is an 'Event'
			if _values[i] == true:
				data[i / 8] |= (1 << (i % 8))
				# Events value is implied by it's flag
			else: continue
		# Property: use baseline for delta comparison
		if baseline == null || not _values_equal(_values[i], baseline._values[i], _types[i]):
			data[i / 8] |= (1 << (i % 8))
			body.append_array(_encode_value(_values[i], _types[i]))
	
	data.append_array(body)
	return data
 
## Decode a [PackedByteArray] produced by [method encode] and apply.
## [param baseline] provides values for values not included due to delta-encoding.
## 'Events' are the last [param event_count] entries, they are assumed false if not present
## Returns bytes consumed after reading, or -1 on error.
func decode(data: PackedByteArray, offset: int, baseline: Snapshot, event_count: int = 0) -> int:
	var property_count: int = size() - event_count
	var flag_bytes: int = ceili(size() / 8.0) if size() > 0 else 0
	
	if offset + flag_bytes > data.size():
		return -1
	var cursor := offset + flag_bytes
	var present: bool # So we only allocate once
	
	for i in size():
		present = (data[offset + i / 8] & (1 << (i % 8))) != 0
		if i >= property_count: # Event
			_values[i] = present
			continue
		# Property
		if not present: # Use baseline
			if baseline != null and baseline.size() > i:
				_values[i] = baseline._values[i]
			continue
		var result: Array = _decode_value(data, cursor, _types[i])
		if result.is_empty():
			return -1
		_values[i] = result[0]
		cursor = result[1]
		
	return cursor

## Returns byte encoded value based on type
static func _encode_value(value: Variant, type: Variant.Type) -> PackedByteArray:
	var bytes := PackedByteArray()
	match type:
		TYPE_BOOL:
			bytes.resize(1)
			bytes[0] = 1 if value else 0
		TYPE_INT:
			bytes.resize(4)
			bytes.encode_s32(0, int(value))
		TYPE_FLOAT:
			bytes.resize(4)
			bytes.encode_float(0, float(value))
		TYPE_VECTOR2:
			bytes.resize(8)
			bytes.encode_float(0, (value as Vector2).x)
			bytes.encode_float(4, (value as Vector2).y)
		TYPE_VECTOR2I:
			bytes.resize(8)
			bytes.encode_s32(0, (value as Vector2i).x)
			bytes.encode_s32(4, (value as Vector2i).y)
		TYPE_VECTOR3:
			bytes.resize(12)
			bytes.encode_float(0, (value as Vector3).x)
			bytes.encode_float(4, (value as Vector3).y)
			bytes.encode_float(8, (value as Vector3).z)
		TYPE_VECTOR3I:
			bytes.resize(12)
			bytes.encode_s32(0, (value as Vector3i).x)
			bytes.encode_s32(4, (value as Vector3i).y)
			bytes.encode_s32(8, (value as Vector3i).z)
		TYPE_VECTOR4:
			bytes.resize(16)
			bytes.encode_float(0,  (value as Vector4).x)
			bytes.encode_float(4,  (value as Vector4).y)
			bytes.encode_float(8,  (value as Vector4).z)
			bytes.encode_float(12, (value as Vector4).w)
		TYPE_QUATERNION:
			bytes.resize(16)
			bytes.encode_float(0,  (value as Quaternion).x)
			bytes.encode_float(4,  (value as Quaternion).y)
			bytes.encode_float(8,  (value as Quaternion).z)
			bytes.encode_float(12, (value as Quaternion).w)
		TYPE_COLOR:
			bytes.resize(16)
			bytes.encode_float(0,  (value as Color).r)
			bytes.encode_float(4,  (value as Color).g)
			bytes.encode_float(8,  (value as Color).b)
			bytes.encode_float(12, (value as Color).a)
		TYPE_BASIS:
			bytes.resize(36)
			var bv := value as Basis
			var off := 0
			for row in [bv.x, bv.y, bv.z]:
				bytes.encode_float(off, row.x)
				bytes.encode_float(off + 4, row.y)
				bytes.encode_float(off + 8, row.z)
				off += 12
		TYPE_TRANSFORM2D:
			bytes.resize(24)
			var t2 := value as Transform2D
			bytes.encode_float(0, t2.x.x)
			bytes.encode_float(4, t2.x.y)
			bytes.encode_float(8, t2.y.x)
			bytes.encode_float(12, t2.y.y)
			bytes.encode_float(16, t2.origin.x)
			bytes.encode_float(20, t2.origin.y)
		TYPE_TRANSFORM3D:
			bytes.resize(48)
			var t3 := value as Transform3D
			var off2 := 0
			for row in [t3.basis.x, t3.basis.y, t3.basis.z]:
				bytes.encode_float(off2, row.x)
				bytes.encode_float(off2+4, row.y)
				bytes.encode_float(off2+8, row.z)
				off2 += 12
			bytes.encode_float(36, t3.origin.x)
			bytes.encode_float(40, t3.origin.y)
			bytes.encode_float(44, t3.origin.z)
		_: # Fallback: var_to_bytes with 4-byte length prefix
			var raw := var_to_bytes(value)
			bytes.resize(4)
			bytes.encode_u16(0, raw.size())
			bytes.append_array(raw)
	return bytes
 
## Returns array with [decoded_value, new_cursor], or [] on failure.
static func _decode_value(data: PackedByteArray, cursor: int, type: Variant.Type) -> Array:
	match type:
		TYPE_BOOL:
			if cursor + 1 > data.size(): return []
			return [data[cursor] != 0, cursor + 1]
		TYPE_INT:
			if cursor + 4 > data.size(): return []
			return [data.decode_s32(cursor), cursor + 4]
		TYPE_FLOAT:
			if cursor + 4 > data.size(): return []
			return [data.decode_float(cursor), cursor + 4]
		TYPE_VECTOR2:
			if cursor + 8 > data.size(): return []
			return [Vector2(data.decode_float(cursor), data.decode_float(cursor+4)), cursor + 8]
		TYPE_VECTOR2I:
			if cursor + 8 > data.size(): return []
			return [Vector2i(data.decode_s32(cursor), data.decode_s32(cursor+4)), cursor + 8]
		TYPE_VECTOR3:
			if cursor + 12 > data.size(): return []
			return [
				Vector3(data.decode_float(cursor), data.decode_float(cursor+4), data.decode_float(cursor+8)),
				cursor + 12
				]
		TYPE_VECTOR3I:
			if cursor + 12 > data.size(): return []
			return [
				Vector3i(data.decode_s32(cursor), data.decode_s32(cursor+4), data.decode_s32(cursor+8)),
				cursor + 12
				]
		TYPE_VECTOR4:
			if cursor + 16 > data.size(): return []
			return [
				Vector4(data.decode_float(cursor), data.decode_float(cursor+4), data.decode_float(cursor+8), data.decode_float(cursor+12)),
				cursor + 16
				]
		TYPE_QUATERNION:
			if cursor + 16 > data.size(): return []
			return [
				Quaternion(data.decode_float(cursor), data.decode_float(cursor+4), data.decode_float(cursor+8), data.decode_float(cursor+12)),
				cursor + 16
				]
		TYPE_COLOR:
			if cursor + 16 > data.size(): return []
			return [
				Color(data.decode_float(cursor), data.decode_float(cursor+4), data.decode_float(cursor+8), data.decode_float(cursor+12)),
				cursor + 16
				]
		TYPE_BASIS:
			if cursor + 36 > data.size(): return []
			var bx := Vector3(data.decode_float(cursor), data.decode_float(cursor+4), data.decode_float(cursor+8))
			var by := Vector3(data.decode_float(cursor+12), data.decode_float(cursor+16), data.decode_float(cursor+20))
			var bz := Vector3(data.decode_float(cursor+24), data.decode_float(cursor+28), data.decode_float(cursor+32))
			return [Basis(bx, by, bz), cursor + 36]
		TYPE_TRANSFORM2D:
			if cursor + 24 > data.size(): return []
			var cx := Vector2(data.decode_float(cursor), data.decode_float(cursor+4))
			var cy := Vector2(data.decode_float(cursor+8),  data.decode_float(cursor+12))
			var co := Vector2(data.decode_float(cursor+16), data.decode_float(cursor+20))
			return [Transform2D(cx, cy, co), cursor + 24]
		TYPE_TRANSFORM3D:
			if cursor + 48 > data.size(): return []
			var tx := Vector3(data.decode_float(cursor), data.decode_float(cursor+4), data.decode_float(cursor+8))
			var ty := Vector3(data.decode_float(cursor+12), data.decode_float(cursor+16), data.decode_float(cursor+20))
			var tz := Vector3(data.decode_float(cursor+24), data.decode_float(cursor+28), data.decode_float(cursor+32))
			var to := Vector3(data.decode_float(cursor+36), data.decode_float(cursor+40), data.decode_float(cursor+44))
			return [Transform3D(Basis(tx, ty, tz), to), cursor + 48]
		_:
			if cursor + 4 > data.size(): return []
			var length: int = data.decode_u16(cursor)
			if cursor + 4 + length > data.size(): return []
			return [bytes_to_var(data.slice(cursor + 4, cursor + 4 + length)), cursor + 4 + length]
 
## Byte size of an encoded value for a given type. -1 for variable-length types.
static func encoded_size(type: Variant.Type) -> int:
	match type:
		TYPE_BOOL: return 1
		TYPE_INT: return 4
		TYPE_FLOAT: return 4
		TYPE_VECTOR2: return 8
		TYPE_VECTOR2I: return 8
		TYPE_VECTOR3: return 12
		TYPE_VECTOR3I: return 12
		TYPE_VECTOR4: return 16
		TYPE_QUATERNION: return 16
		TYPE_COLOR: return 16
		TYPE_BASIS: return 36
		TYPE_TRANSFORM2D: return 24
		TYPE_TRANSFORM3D: return 48
		_: return -1
 
## Determines if two values are equal for purposes of delta-encoding
static func _values_equal(a: Variant, b: Variant, type: Variant.Type) -> bool:
	match type:
		TYPE_FLOAT: return is_equal_approx(float(a), float(b))
		TYPE_VECTOR2: return (a as Vector2).is_equal_approx(b)
		TYPE_VECTOR3: return (a as Vector3).is_equal_approx(b)
		TYPE_VECTOR4: return (a as Vector4).is_equal_approx(b)
		TYPE_QUATERNION: return (a as Quaternion).is_equal_approx(b)
		TYPE_COLOR: return (a as Color).is_equal_approx(b)
		_: return a == b
