class_name NetState
extends NetBase
## Syncs server variables with all clients

func _on_tick() -> void:
	pass

func _decode(tick: int, data: PackedByteArray) -> void:
	pass

func _encode(tick: int) -> PackedByteArray:
	var data: PackedByteArray
	return data
