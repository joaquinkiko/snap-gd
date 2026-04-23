class_name NetInput
extends NetBase
## Syncs client variables and events with server

func _on_tick() -> void:
	pass

func _decode(tick: int, data: PackedByteArray) -> void:
	pass

func _encode(tick: int) -> PackedByteArray:
	var data: PackedByteArray
	return data
